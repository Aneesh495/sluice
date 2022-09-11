#import "SLReactor.h"
#import "SLNet.h"
#import "SLWire.h"
#import "SLReceipt.h"
#import "SLBytes.h"
#import "SLJSON.h"
#import "SLError.h"
#import <poll.h>
#import <sys/socket.h>
#import <fcntl.h>
#import <unistd.h>

@implementation SLReactor {
    SLSession *_session;
    SLEndpoint *_upstream;
    NSArray<NSData *> *_addresses;
    NSMutableArray<SLConnection *> *_connections;
    int _listener;
    int _wakeRead;
    int _wakeWrite;
    uint16_t _requestedPort;
    BOOL _stopping;
}
- (instancetype)initSession:(SLSession *)session upstream:(SLEndpoint *)upstream port:(uint16_t)port {
    if ((self=[super init])) {
        _listener=-1; _wakeRead=-1; _wakeWrite=-1; _session=session; _upstream=upstream; _requestedPort=port;
        SLRequire(![session.mode isEqual:@"record"] || upstream!=nil,@"reactor.upstream",@"Recording requires an upstream endpoint");
        if (upstream) _addresses=SLResolve(upstream);
        _connections=[NSMutableArray array];
        int descriptors[2]; SLRequire(pipe(descriptors)==0,@"reactor.pipe",@"Cannot create reactor wake pipe");
        _wakeRead=descriptors[0]; _wakeWrite=descriptors[1];
        for (int i=0;i<2;i++) SLRequire(fcntl(descriptors[i],F_SETFL,O_NONBLOCK)==0 && fcntl(descriptors[i],F_SETFD,FD_CLOEXEC)==0,@"reactor.pipe",@"Cannot configure reactor wake pipe");
    } return self;
}
- (void)dealloc { if (_listener>=0) close(_listener); if (_wakeRead>=0) close(_wakeRead); if (_wakeWrite>=0) close(_wakeWrite); }
- (void)stop { uint8_t b=1; if (_wakeWrite>=0) { ssize_t ignored=write(_wakeWrite,&b,1); (void)ignored; } }
- (void)receipt:(SLConnection *)c {
    if (c.receiptWritten) return; c.receiptWritten=YES;
    @try {
        NSDictionary *receipt=SLMakeReceipt(_session.identifier,_session.mode,c.context.identity ?: @"",c.context.occurrence,c.context.fixture,c.plan.summary,c.acceptedBytes,SLNowUS()-c.startedUS,c.outcome,c.errorCode);
        [_session.store saveReceipt:receipt];
    } @catch (SLError *e) { _fatalError=e.code; _stopping=YES; }
}
- (void)finish:(SLConnection *)c outcome:(NSString *)outcome {
    c.outcome=outcome; [self receipt:c]; [c close]; _completedConnections++;
}
- (void)deliver:(SLConnection *)c response:(SLMessage *)response {
    c.plan=[_session complete:c.context request:c.requestParser.message response:response];
    [c closeOrigin]; c.originWire=nil; c.responseParser=nil;
    c.planStartUS=SLNowUS(); c.activeUS=c.planStartUS; c.state=SLDeliveringResponse;
}
- (void)failure:(SLConnection *)c code:(NSString *)code status:(NSInteger)status outcome:(NSString *)outcome {
    c.errorCode=code; c.outcome=outcome; [c closeOrigin];
    // Error payloads carry stable codes only. A parser diagnostic must not echo
    // credentials or arbitrary malformed request bytes back into the ledger.
    SLMessage *response=[SLMessage response:status body:SLJSONData(@{@"error":code}) contentType:@"application/json"];
    SLMessage *request=c.requestParser.message ?: [SLMessage new];
    c.plan=[[SLDeliveryPlan alloc] initResponse:response request:request rule:nil scenario:SLScenario.passthrough identity:c.context.identity ?: @"" occurrence:c.context.occurrence ?: 1];
    if (!c.context) { c.context=[SLRequestContext new]; c.context.identity=@""; c.context.occurrence=1; }
    c.planStartUS=SLNowUS(); c.activeUS=c.planStartUS; c.state=SLDeliveringResponse;
}
- (void)connectOrigin:(SLConnection *)c {
    [c closeOrigin];
    while (c.addressIndex<_addresses.count) {
        @try { c.originFD=SLConnect(_addresses[c.addressIndex++]); c.state=SLConnectingOrigin; return; }
        @catch (SLError *e) { if (c.addressIndex==_addresses.count) @throw; }
    }
    SLFail(@"net.connect",@"All upstream addresses failed");
}
- (void)requestReady:(SLConnection *)c {
    c.context=[_session begin:c.requestParser.message];
    if ([_session.mode isEqual:@"replay"]) [self deliver:c response:[_session replay:c.context]];
    else {
        c.originWire=SLWireRequest(c.requestParser.message,_upstream);
        c.responseParser=[[SLHTTPParser alloc] initRequest:NO responseToHEAD:[c.requestParser.message.method isEqual:@"HEAD"]];
        [self connectOrigin:c];
    }
}
- (void)readClient:(SLConnection *)c {
    uint8_t buffer[16384]; ssize_t n=recv(c.clientFD,buffer,sizeof(buffer),0);
    if (n<0) { if (SLWouldBlock()) return; [self finish:c outcome:@"client-closed"]; return; }
    if (!n) { [self finish:c outcome:@"client-closed"]; return; }
    c.activeUS=SLNowUS();
    [c.requestParser feed:[NSData dataWithBytes:buffer length:(NSUInteger)n]];
    if (c.requestParser.complete) [self requestReady:c];
}
- (void)originEvent:(SLConnection *)c events:(short)events {
    if (c.state==SLConnectingOrigin) {
        int error=0; socklen_t size=sizeof(error);
        SLRequire(getsockopt(c.originFD,SOL_SOCKET,SO_ERROR,&error,&size)==0,@"net.connect",@"Cannot inspect upstream connection");
        if (error) { [self connectOrigin:c]; return; }
        c.state=SLWritingOrigin; c.activeUS=SLNowUS();
    }
    if (c.state==SLWritingOrigin && (events&POLLOUT)) {
        ssize_t n=send(c.originFD,(const uint8_t *)c.originWire.bytes+c.originWritten,c.originWire.length-c.originWritten,0);
        if (n<0) { if (SLWouldBlock()) return; SLFail(@"net.write",@"Upstream write failed"); }
        c.originWritten+=(NSUInteger)n; if (n) c.activeUS=SLNowUS();
        if (c.originWritten==c.originWire.length) { c.state=SLReadingOrigin; c.originWire=nil; }
    }
    if (c.state==SLReadingOrigin && (events&(POLLIN|POLLHUP))) {
        uint8_t buffer[16384]; ssize_t n=recv(c.originFD,buffer,sizeof(buffer),0);
        if (n<0) { if (SLWouldBlock()) return; SLFail(@"net.read",@"Upstream read failed"); }
        if (!n) [c.responseParser endOfFile];
        else { c.activeUS=SLNowUS(); [c.responseParser feed:[NSData dataWithBytes:buffer length:(NSUInteger)n]]; }
        if (c.responseParser.complete) [self deliver:c response:c.responseParser.message];
    }
    if (c.state!=SLDeliveringResponse && (events&(POLLERR|POLLNVAL))) SLFail(@"net.origin",@"Upstream socket failed");
}
- (void)writeClient:(SLConnection *)c {
    uint64_t elapsed=SLNowUS()-c.planStartUS;
    if (!c.plan.segmentCount) { if (elapsed>=c.plan.delayUS) [self finish:c outcome:c.outcome]; return; }
    NSUInteger budget=65536;
    while (c.segment<c.plan.segmentCount && budget>0 && elapsed>=[c.plan dueUSAt:c.segment]) {
        NSRange range=[c.plan rangeAt:c.segment]; NSUInteger remaining=range.length-c.segmentWritten;
        NSUInteger count=MIN(remaining,budget);
        ssize_t n=send(c.clientFD,(const uint8_t *)c.plan.wire.bytes+range.location+c.segmentWritten,count,0);
        if (n<0) { if (SLWouldBlock()) return; [self finish:c outcome:@"client-closed"]; return; }
        if (!n) return;
        c.acceptedBytes+=(NSUInteger)n; c.segmentWritten+=(NSUInteger)n; budget-=(NSUInteger)n; c.activeUS=SLNowUS();
        if (c.segmentWritten==range.length) { c.segment++; c.segmentWritten=0; }
    }
    if (c.segment==c.plan.segmentCount) [self finish:c outcome:c.outcome];
}
- (void)acceptClients {
    for (NSUInteger i=0;i<32;i++) {
        int fd=accept(_listener,NULL,NULL); if (fd<0) { if (SLWouldBlock()) return; SLFail(@"net.accept",@"Cannot accept client"); }
        if (_connections.count>=64) { close(fd); continue; }
        @try { SLNonblocking(fd); [_connections addObject:[[SLConnection alloc] initWithSocket:fd]]; }
        @catch (NSException *e) { close(fd); @throw; }
    }
}
- (void)runReady:(void (^)(uint16_t))ready {
    SLRequire(!self.running,@"reactor.running",@"Reactor is already running");
    _listener=SLListen(_requestedPort,&_port); _running=YES;
    @try {
        ready(self.port);
        while (!_stopping) { @autoreleasepool {
            struct pollfd fds[130]; SLConnection *__strong owners[130]; BOOL origins[130];
            memset(fds,0,sizeof(fds)); memset(origins,0,sizeof(origins));
            fds[0]=(struct pollfd){_listener,POLLIN,0}; fds[1]=(struct pollfd){_wakeRead,POLLIN,0}; NSUInteger count=2;
            uint64_t now=SLNowUS(); int timeout=100;
            for (SLConnection *c in _connections) {
                short clientEvents=c.state==SLReadingRequest?POLLIN:0;
                if (c.state==SLDeliveringResponse) {
                    uint64_t due=c.plan.segmentCount?[c.plan dueUSAt:c.segment]:c.plan.delayUS;
                    uint64_t elapsed=now-c.planStartUS;
                    if (elapsed>=due) {
                        if (!c.plan.segmentCount) { [self finish:c outcome:c.outcome]; continue; }
                        clientEvents=POLLOUT;
                    } else timeout=MIN(timeout,(int)MIN((due-elapsed+999)/1000,(uint64_t)100));
                }
                if (c.state==SLConnectionClosed) continue;
                fds[count]=(struct pollfd){c.clientFD,clientEvents,0}; owners[count]=c; count++;
                if (c.originFD>=0) {
                    short interest=c.state==SLReadingOrigin?POLLIN:POLLOUT;
                    fds[count]=(struct pollfd){c.originFD,interest,0}; owners[count]=c; origins[count]=YES; count++;
                }
            }
            int rc=poll(fds,(nfds_t)count,timeout);
            if (rc<0) { if (errno==EINTR) continue; SLFail(@"net.poll",@"Socket poll failed"); }
            if (fds[1].revents) { _stopping=YES; break; }
            if (fds[0].revents&POLLIN) [self acceptClients];
            for (NSUInteger i=2;i<count;i++) {
                SLConnection *c=owners[i]; if (c.state==SLConnectionClosed || !fds[i].revents) continue;
                @try {
                    if (origins[i]) [self originEvent:c events:fds[i].revents];
                    else if (c.state==SLReadingRequest && (fds[i].revents&POLLIN)) [self readClient:c];
                    else if (c.state==SLDeliveringResponse && (fds[i].revents&POLLOUT)) [self writeClient:c];
                    if (c.state!=SLConnectionClosed && !origins[i] && (fds[i].revents&(POLLERR|POLLNVAL|POLLHUP))) [self finish:c outcome:@"client-closed"];
                } @catch (SLError *e) {
                    NSInteger status=[e.code hasPrefix:@"replay."]?409:(origins[i] || c.originFD>=0)?502:400;
                    @try { [self failure:c code:e.code status:status outcome:origins[i]?@"upstream-error":@"engine-error"]; }
                    @catch (SLError *nested) { c.errorCode=nested.code; [self finish:c outcome:@"engine-error"]; }
                }
            }
            now=SLNowUS();
            for (SLConnection *c in _connections) if (c.state!=SLConnectionClosed) {
                BOOL waitingForPlan=c.state==SLDeliveringResponse;
                if (now-c.startedUS>125000000 || (!waitingForPlan && now-c.activeUS>10000000)) { c.errorCode=@"net.timeout"; [self finish:c outcome:@"timeout"]; }
                else if (waitingForPlan && c.plan.segmentCount && now-c.activeUS>15000000 && now-c.planStartUS>=[c.plan dueUSAt:c.segment]) { c.errorCode=@"net.backpressure"; [self finish:c outcome:@"timeout"]; }
            }
            NSIndexSet *closed=[_connections indexesOfObjectsPassingTest:^BOOL(SLConnection *c, NSUInteger index, BOOL *stop) { return c.state==SLConnectionClosed; }];
            [_connections removeObjectsAtIndexes:closed]; _activeConnections=_connections.count;
        }}
    } @finally {
        for (SLConnection *c in _connections) if (c.state!=SLConnectionClosed) [self finish:c outcome:@"shutdown"];
        [_connections removeAllObjects]; _activeConnections=0; close(_listener); _listener=-1; _running=NO;
    }
}
@end
