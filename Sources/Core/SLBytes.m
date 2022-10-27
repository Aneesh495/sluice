#import "SLBytes.h"
#import "SLError.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
NSData *SLUTF8(NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    SLRequire(data != nil, @"text.encoding", @"String cannot be represented as UTF-8");
    return data;
}
NSString *SLDecodeUTF8(NSData *data) {
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    SLRequire(s != nil, @"text.encoding", @"Invalid UTF-8");
    return s;
}
NSString *SLSHA256(NSData *data) {
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    const uint8_t *p = data.bytes;
    NSUInteger at = 0;
    while (at < data.length) {
        CC_LONG count = (CC_LONG)MIN(data.length - at, (NSUInteger)UINT32_MAX);
        CC_SHA256_Update(&ctx, p + at, count);
        at += count;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    char hex[65];
    static const char digits[] = "0123456789abcdef";
    for (NSUInteger i = 0; i < 32; i++) {
        hex[2 * i] = digits[digest[i] >> 4];
        hex[2 * i + 1] = digits[digest[i] & 15];
    }
    hex[64] = 0;
    return @(hex);
}
NSData *SLReadFile(NSString *path, NSUInteger limit) {
    // O_NOFOLLOW prevents a workspace file from becoming an arbitrary symlink
    // read. fstat on the opened descriptor closes the check/open race.
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    SLRequire(fd >= 0, @"file.open", @"Cannot open input file");
    @try {
        struct stat st;
        SLRequire(fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size >= 0 &&
                      (uint64_t)st.st_size <= limit,
                  @"file.limit", @"Input must be a regular file within the byte limit");
        NSMutableData *result = [NSMutableData data];
        uint8_t buffer[16384];
        while (YES) {
            ssize_t n = read(fd, buffer, sizeof(buffer));
            if (n < 0 && errno == EINTR)
                continue;
            SLRequire(n >= 0, @"file.read", @"Cannot read input file");
            if (!n)
                break;
            SLRequire((NSUInteger)n <= limit - result.length, @"file.limit",
                      @"Input grew past the byte limit");
            [result appendBytes:buffer length:(NSUInteger)n];
        }
        return result;
    } @finally {
        close(fd);
    }
}
void SLAtomicWrite(NSData *data, NSString *path) {
    NSString *parent = [path stringByDeletingLastPathComponent];
    if (!parent.length)
        parent = @".";
    NSString *temporary =
        [parent stringByAppendingPathComponent:[@".sluice-"
                                                   stringByAppendingString:NSUUID.UUID.UUIDString]];
    int fd =
        open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    SLRequire(fd >= 0, @"file.create", @"Cannot create output staging file");
    @try {
        NSUInteger at = 0;
        while (at < data.length) {
            ssize_t n = write(fd, (const uint8_t *)data.bytes + at, data.length - at);
            if (n < 0 && errno == EINTR)
                continue;
            SLRequire(n > 0, @"file.write", @"Cannot write output staging file");
            at += (NSUInteger)n;
        }
        SLRequire(fsync(fd) == 0, @"file.sync", @"Cannot synchronize output");
        SLRequire(rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0,
                  @"file.rename", @"Cannot publish output");
        int dir = open(parent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (dir >= 0) {
            fsync(dir);
            close(dir);
        }
    } @finally {
        close(fd);
        unlink(temporary.fileSystemRepresentation);
    }
}
NSUInteger SLFindBytes(NSData *data, const char *needle, NSUInteger length, NSUInteger start) {
    if (start > data.length || length > data.length - start)
        return NSNotFound;
    const uint8_t *p = data.bytes;
    for (NSUInteger i = start; i <= data.length - length; i++)
        if (!memcmp(p + i, needle, length))
            return i;
    return NSNotFound;
}
BOOL SLToken(NSString *value) {
    NSData *d = [value dataUsingEncoding:NSASCIIStringEncoding];
    if (!d.length)
        return NO;
    const uint8_t *p = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) {
        uint8_t c = p[i];
        if (!(isalnum(c) || strchr("!#$%&'*+-.^_`|~", c)))
            return NO;
    }
    return YES;
}
BOOL SLFieldValue(NSString *value) {
    NSData *d = [value dataUsingEncoding:NSISOLatin1StringEncoding];
    if (!d)
        return NO;
    const uint8_t *p = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++)
        if ((p[i] < 32 && p[i] != 9) || p[i] == 127)
            return NO;
    return YES;
}
