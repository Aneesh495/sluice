#import "SLChunkDecoder.h"
#import "SLBytes.h"
#import "SLError.h"
@implementation SLChunkDecoder {
    NSMutableData *_pending;
    NSMutableData *_decoded;
    NSUInteger _remaining;
    NSInteger _state; // 0 size, 1 bytes, 2 chunk CRLF, 3 final CRLF, 4 done
}
- (instancetype)init { if ((self=[super init])) { _pending=[NSMutableData data]; _decoded=[NSMutableData data]; } return self; }
- (NSData *)body { return [_decoded copy]; }
- (BOOL)complete { return _state==4; }
- (void)consume:(NSUInteger)n { [_pending replaceBytesInRange:NSMakeRange(0,n) withBytes:NULL length:0]; }
- (void)feed:(NSData *)data {
    SLRequire(data.length<=8*1024*1024+65536-_pending.length,@"http.body-limit",@"Chunk input exceeds buffer budget");
    [_pending appendData:data];
    while (YES) {
        if (_state==4) { SLRequire(!_pending.length,@"http.trailing",@"Bytes follow completed message"); return; }
        if (_state==0) {
            NSUInteger line=SLFindBytes(_pending,"\r\n",2,0);
            if (line==NSNotFound) { SLRequire(_pending.length<=128,@"http.chunk",@"Chunk size line is too long"); return; }
            SLRequire(line>0 && line<=16,@"http.chunk",@"Chunk size must be bounded hexadecimal without extensions");
            const uint8_t *p=_pending.bytes; NSUInteger n=0;
            for (NSUInteger i=0;i<line;i++) {
                uint8_t c=p[i]; NSInteger digit=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:-1;
                SLRequire(digit>=0,@"http.chunk",@"Invalid chunk size");
                SLRequire(n<=(8*1024*1024-(NSUInteger)digit)/16,@"http.body-limit",@"Chunk size exceeds body budget"); n=n*16+(NSUInteger)digit;
            }
            SLRequire(n<=8*1024*1024-_decoded.length,@"http.body-limit",@"Decoded body exceeds 8 MiB");
            _remaining=n; [self consume:line+2]; _state=n?1:3;
        } else if (_state==1) {
            NSUInteger n=MIN(_remaining,_pending.length);
            [_decoded appendBytes:_pending.bytes length:n]; [self consume:n]; _remaining-=n;
            if (_remaining) return; _state=2;
        } else {
            if (_pending.length<2) return;
            SLRequire(!memcmp(_pending.bytes,"\r\n",2),@"http.chunk",@"Malformed chunk terminator or unsupported trailers");
            [self consume:2]; _state=_state==3?4:0;
        }
    }
}
@end
