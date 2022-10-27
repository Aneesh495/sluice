#import "SLConnection.h"
#import "SLNet.h"
#import <unistd.h>
@implementation SLConnection
- (instancetype)initWithSocket:(int)fd {
    if ((self = [super init])) {
        _clientFD = fd;
        _originFD = -1;
        _state = SLReadingRequest;
        _requestParser = [[SLHTTPParser alloc] initRequest:YES responseToHEAD:NO];
        _startedUS = SLNowUS();
        _activeUS = _startedUS;
        _outcome = @"complete";
    }
    return self;
}
- (void)closeOrigin {
    if (_originFD >= 0) {
        close(_originFD);
        _originFD = -1;
    }
}
- (void)close {
    [self closeOrigin];
    if (_clientFD >= 0) {
        close(_clientFD);
        _clientFD = -1;
    }
    self.state = SLConnectionClosed;
}
- (void)dealloc {
    [self close];
}
@end
