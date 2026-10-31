import Foundation
import Darwin

/// Minimal POSIX serial port for macOS (/dev/cu.*), 8N1, no flow control.
final class SerialPort {
    let path: String
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "acom.serial")
    var onData: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?

    var isOpen: Bool { fd >= 0 }

    init(path: String) { self.path = path }

    /// Lists USB-serial and other serial devices. macOS exposes each twice
    /// (tty.* and cu.*); the cu.* "call-out" node is the right one to open.
    static func availablePorts() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return items.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "/dev/" + $0 }
    }

    func open(baud: speed_t = speed_t(B9600)) throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.open(String(cString: strerror(errno))) }

        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetispeed(&t, baud)
        cfsetospeed(&t, baud)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE | CCTS_OFLOW | CRTS_IFLOW)
        t.c_cflag |= tcflag_t(CS8)
        t.c_cflag &= ~tcflag_t(HUPCL)          // don't toggle DTR on close
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            let msg = String(cString: strerror(errno)); close(); throw SerialError.open(msg)
        }

        // ACOM: hold DTR and RTS low, otherwise the front-panel power button
        // on 700S / 2020S can be blocked.
        setModemLines(dtr: false, rts: false)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 512)
            let n = read(self.fd, &buf, buf.count)
            if n > 0 {
                self.onData?(Array(buf[0..<n]))
            } else if n == 0 || (n < 0 && errno != EAGAIN) {
                self.close()          // USB adapter unplugged
                self.onClose?()
            }
        }
        readSource = src
        src.resume()
    }

    func write(_ bytes: [UInt8]) {
        guard fd >= 0 else { return }
        _ = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    func setModemLines(dtr: Bool, rts: Bool) {
        guard fd >= 0 else { return }
        // The ioctl request codes are function-like C macros Swift can't import.
        let kTIOCMBIS: UInt = 0x8004_746C   // _IOW('t', 108, int)
        let kTIOCMBIC: UInt = 0x8004_746B   // _IOW('t', 107, int)
        let kDTR: Int32 = 0x002, kRTS: Int32 = 0x004
        var set: Int32 = 0, clear: Int32 = 0
        if dtr { set |= kDTR } else { clear |= kDTR }
        if rts { set |= kRTS } else { clear |= kRTS }
        if set != 0 { _ = withUnsafeMutablePointer(to: &set) { ioctl(fd, kTIOCMBIS, $0) } }
        if clear != 0 { _ = withUnsafeMutablePointer(to: &clear) { ioctl(fd, kTIOCMBIC, $0) } }
    }

    func close() {
        readSource?.cancel()
        readSource = nil
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    deinit { close() }

    enum SerialError: LocalizedError {
        case open(String)
        var errorDescription: String? {
            switch self { case .open(let m): return "Couldn't open port: \(m)" }
        }
    }
}
