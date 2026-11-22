"tests/uefi/fat.sh: run on UEFI with the FAT disks it attaches; each finding a line fat ... (tests/uefi/fat.expected). One expression: the script joins the lines."
| f lf err data report |
lf := String with: Character lf.
f := [:x | Smalltalk vm stderrWrite: 'fat ', x, lf].
err := [:block | [block value. 'no error'] on: FileError do: [:e | e class name, ' ', e messageText]].
f value: 'mounts ', (FirmwareVolumes mounts collect: [:m | m key]) printString.
f value: 'problems ', FirmwareVolumes problems printString.
f value: 'labels ', ((FirmwareFileSystem all collect: [:v | v label]) asSortedCollection: [:a :b | a <= b]) asArray printString.
data := ((0 to: 99999) collect: [:i | i * 7 \\ 256]) asByteArray.
Directory create: '/esp/samaltak-test'.
File writeBytes: data to: '/esp/samaltak-test/data.bin'.
f value: 'esp data ', (File sizeOf: '/esp/samaltak-test/data.bin') printString, ' ', ((File readBytes: '/esp/samaltak-test/data.bin') = data) printString.
f value: 'hello ', (File readText: '/mnt/FATDATA/hello.txt') lines first.
File writeText: 'first line', lf to: '/mnt/FATDATA/notes.txt'.
FileStream withStream: (FileStream appendingFileNamed: '/mnt/FATDATA/notes.txt') do: [:s | s nextPutAll: 'second line'; nextPutAll: lf].
FileStream fileNamed: '/mnt/FATDATA/notes.txt' do: [:s | s position: 0. s nextPutAll: 'FIRST'].
f value: 'notes ', (File readText: '/mnt/FATDATA/notes.txt') lines printString.
Directory create: '/mnt/FATDATA/sub'.
File writeText: 'move me' to: '/mnt/FATDATA/old.txt'.
File rename: '/mnt/FATDATA/old.txt' to: '/mnt/FATDATA/sub/new.txt'.
File writeText: 'gone' to: '/mnt/FATDATA/gone.txt'.
File delete: '/mnt/FATDATA/gone.txt'.
File writeText: 'a long name' to: '/mnt/FATDATA/A long file name.text'.
File writeText: 'something longer' to: '/mnt/FATDATA/short.txt'.
File writeText: 'short' to: '/mnt/FATDATA/short.txt'.
f value: 'short ', (File readText: '/mnt/FATDATA/short.txt'), ' ', (File sizeOf: '/mnt/FATDATA/short.txt') printString.
f value: 'entries ', (Directory entries: '/mnt/FATDATA') printString.
f value: 'sub ', (Directory entries: '/mnt/FATDATA/sub') printString, ' ', (File readText: '/mnt/FATDATA/sub/new.txt').
f value: 'mtime ', ((File modificationTime: '/mnt/FATDATA/notes.txt') > 1700000000000000) printString.
f value: 'not empty ', (err value: [File delete: '/mnt/FATDATA/sub']).
f value: 'exists ', (err value: [Directory create: '/mnt/FATDATA/sub']).
f value: 'missing ', (err value: [File readText: '/mnt/FATDATA/missing.txt']).
f value: 'no directory ', (err value: [File writeText: 'x' to: '/mnt/FATDATA/nodir/x.txt']).
f value: 'other volume ', (err value: [File rename: '/mnt/FATDATA/sub/new.txt' to: '/esp/new.txt']).
f value: 'read-only write ', (err value: [File writeText: 'x' to: '/mnt/FATRO/x.txt']).
f value: 'read-only delete ', (err value: [File delete: '/mnt/FATRO/ro.txt']).
f value: 'read-only mkdir ', (err value: [Directory create: '/mnt/FATRO/d']).
f value: 'read-only read ', (File readText: '/mnt/FATRO/ro.txt') lines first.
f value: 'full ', (err value: [File writeBytes: (ByteArray new: 1000000 withAll: 65) to: '/mnt/FATFULL/big.bin']).
f value: 'ext4 ', (err value: [File writeText: 'x' to: '/mnt/fixture/x']).
report := [1 / 0] on: ZeroDivide do: [:e | e return: (CrashReport exception: e context: e signalerContext process: Processor activeProcess) write].
f value: 'report ', report.
f value: 'done'
