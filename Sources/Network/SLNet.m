#import "SLNet.h"
#import "SLError.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <fcntl.h>
#import <unistd.h>
#import <time.h>
uint64_t SLNowUS(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000 + (uint64_t)t.tv_nsec / 1000;
}
BOOL SLWouldBlock(void) {
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR;
}
void SLNonblocking(int fd) {
    SLRequire(fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK) == 0 &&
                  fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              @"net.flags", @"Cannot configure socket flags");
    int one = 1;
    SLRequire(setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) == 0, @"net.flags",
              @"Cannot suppress socket SIGPIPE");
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
}
int SLListen(uint16_t port, uint16_t *actualPort) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    SLRequire(fd >= 0, @"net.socket", @"Cannot create listener");
    @try {
        SLNonblocking(fd);
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        struct sockaddr_in a = {0};
        a.sin_len = sizeof(a);
        a.sin_family = AF_INET;
        a.sin_port = htons(port);
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        SLRequire(bind(fd, (struct sockaddr *)&a, sizeof(a)) == 0 && listen(fd, 128) == 0,
                  @"net.listen", @"Cannot bind loopback listener; port may already be in use");
        socklen_t n = sizeof(a);
        SLRequire(getsockname(fd, (struct sockaddr *)&a, &n) == 0, @"net.address",
                  @"Cannot inspect listener address");
        *actualPort = ntohs(a.sin_port);
        return fd;
    } @catch (NSException *e) {
        close(fd);
        @throw;
    }
}
NSArray *SLResolve(SLEndpoint *endpoint) {
    struct addrinfo hints = {0}, *addresses = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int rc = getaddrinfo(endpoint.host.UTF8String, @(endpoint.port).stringValue.UTF8String, &hints,
                         &addresses);
    SLRequire(rc == 0, @"net.resolve", @"Cannot resolve upstream host");
    NSMutableArray *result = [NSMutableArray array];
    for (struct addrinfo *a = addresses; a && result.count < 16; a = a->ai_next)
        if (a->ai_family == AF_INET || a->ai_family == AF_INET6)
            [result addObject:[NSData dataWithBytes:a->ai_addr length:a->ai_addrlen]];
    freeaddrinfo(addresses);
    SLRequire(result.count > 0, @"net.resolve", @"No upstream IP addresses resolved");
    return result;
}
int SLConnect(NSData *address) {
    const struct sockaddr *a = address.bytes;
    int fd = socket(a->sa_family, SOCK_STREAM, 0);
    SLRequire(fd >= 0, @"net.socket", @"Cannot create upstream socket");
    @try {
        SLNonblocking(fd);
        int rc = connect(fd, a, (socklen_t)address.length);
        SLRequire(rc == 0 || errno == EINPROGRESS, @"net.connect",
                  @"Upstream connection could not start");
        return fd;
    } @catch (NSException *e) {
        close(fd);
        @throw;
    }
}
