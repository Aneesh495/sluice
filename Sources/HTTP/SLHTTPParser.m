#import "SLHTTPParser.h"
#import "SLHead.h"
#import "SLChunkDecoder.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLHTTPParser {
    BOOL _request;
    BOOL _head;
    NSMutableData *_pending;
    NSMutableData *_body;
    SLChunkDecoder *_chunks;
    NSUInteger _length;
    BOOL _untilEOF;
}
- (instancetype)initRequest:(BOOL)request responseToHEAD:(BOOL)head {
    if ((self=[super init])) { _request=request; _head=head; _pending=[NSMutableData data]; _body=[NSMutableData data]; }
    return self;
}
- (BOOL)headComplete { return _message!=nil; }
- (void)finish { _message.body=[_body copy]; _complete=YES; }
- (void)feed:(NSData *)data {
    SLRequire(!_complete || !data.length,@"http.trailing",@"Bytes follow completed message");
    if (_complete) return;
    if (!_message) {
        SLRequire(data.length<=8*1024*1024+65536-_pending.length,@"http.body-limit",@"HTTP input exceeds buffer budget");
        [_pending appendData:data]; NSUInteger split=SLFindBytes(_pending,"\r\n\r\n",4,0);
        if (split==NSNotFound) { SLRequire(_pending.length<=65536,@"http.head-limit",@"HTTP head exceeds 64 KiB"); return; }
        _message=SLParseHead([_pending subdataWithRange:NSMakeRange(0,split+4)],_request);
        data=[_pending subdataWithRange:NSMakeRange(split+4,_pending.length-split-4)]; _pending=nil;
        BOOL present=NO; _length=SLContentLength(_message.headers,&present);
        BOOL noBody=!_request && (_head || _message.status==204 || _message.status==304);
        if (noBody) { _length=0; present=YES; }
        else if ([_message.headers values:@"Transfer-Encoding"].count) _chunks=[SLChunkDecoder new];
        else _untilEOF=!_request && !present;
        if (_request) {
            SLRequire(![_message.headers first:@"Expect"],@"http.expect",@"Expect is unsupported; send the body without a continue handshake");
            SLRequire(![_message.headers first:@"Upgrade"],@"http.upgrade",@"Protocol upgrades are unsupported");
        }
    }
    if (_chunks) {
        [_chunks feed:data];
        if (_chunks.complete) { _body=[_chunks.body mutableCopy]; [self finish]; }
    } else {
        SLRequire(data.length<=8*1024*1024-_body.length,@"http.body-limit",@"HTTP body exceeds 8 MiB");
        [_body appendData:data];
        if (!_untilEOF) {
            SLRequire(_body.length<=_length,@"http.trailing",@"Bytes exceed Content-Length or forbidden body");
            if (_body.length==_length) [self finish];
        }
    }
}
- (void)endOfFile {
    SLRequire(_message!=nil,@"http.incomplete",@"Connection ended before the HTTP head");
    if (_untilEOF) [self finish];
    SLRequire(_complete,@"http.incomplete",@"Connection ended before the HTTP body was complete");
}
@end
