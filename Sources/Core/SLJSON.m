#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"

@interface SLJSONReader : NSObject
@property(nonatomic) NSData *data;
@property(nonatomic) NSUInteger at;
@property(nonatomic) NSUInteger nodes;
- (id)value:(NSUInteger)depth;
@end
@implementation SLJSONReader
- (uint8_t)peek { return self.at<self.data.length ? ((const uint8_t *)self.data.bytes)[self.at] : 0; }
- (void)space { while (self.at<self.data.length && strchr(" \t\r\n",[self peek])) self.at++; }
- (void)take:(uint8_t)c {
    SLRequire(self.at<self.data.length && [self peek]==c,@"json.syntax",@"Unexpected JSON delimiter"); self.at++;
}
- (NSString *)string {
    NSUInteger start=self.at; [self take:'"']; BOOL escaped=NO, closed=NO;
    while (self.at<self.data.length) {
        uint8_t c=[self peek]; self.at++;
        if (!escaped && c=='"') { closed=YES; break; }
        if (!escaped && c=='\\') escaped=YES; else escaped=NO;
    }
    SLRequire(closed,@"json.syntax",@"Unterminated JSON string");
    NSData *slice=[self.data subdataWithRange:NSMakeRange(start,self.at-start)];
    NSError *error=nil;
    id value=[NSJSONSerialization JSONObjectWithData:slice options:NSJSONReadingFragmentsAllowed error:&error];
    SLRequire([value isKindOfClass:NSString.class] && !error,@"json.syntax",@"Invalid JSON string escape or encoding");
    return value;
}
- (id)value:(NSUInteger)depth {
    SLRequire(depth<=32 && ++self.nodes<=100000,@"json.limit",@"JSON depth or node budget exceeded");
    [self space]; uint8_t c=[self peek];
    if (c=='"') return [self string];
    if (c=='{' || c=='[') {
        BOOL object=c=='{'; self.at++; [self space];
        NSMutableDictionary *dict=[NSMutableDictionary dictionary];
        NSMutableArray *array=[NSMutableArray array]; uint8_t end=object?'}':']';
        if ([self peek]==end) { self.at++; return object ? (id)dict : array; }
        while (YES) {
            [self space]; NSString *key=nil;
            if (object) {
                SLRequire([self peek]=='"',@"json.syntax",@"Object key must be a string");
                key=[self string]; SLRequire(dict[key]==nil,@"json.duplicate",@"Duplicate JSON key");
                [self space]; [self take:':'];
            }
            id item=[self value:depth+1];
            if (object) dict[key]=item; else [array addObject:item];
            [self space]; if ([self peek]==end) { self.at++; break; }
            [self take:','];
        }
        return object ? (id)dict : array;
    }
    NSUInteger start=self.at;
    while (self.at<self.data.length && !strchr(" \t\r\n,}]",[self peek])) self.at++;
    SLRequire(self.at>start,@"json.syntax",@"Expected a JSON value");
    NSError *error=nil;
    id value=[NSJSONSerialization JSONObjectWithData:[self.data subdataWithRange:NSMakeRange(start,self.at-start)] options:NSJSONReadingFragmentsAllowed error:&error];
    SLRequire(value && !error && ![value isKindOfClass:NSString.class],@"json.syntax",@"Invalid JSON scalar");
    return value;
}
@end
id SLJSONRead(NSData *data) {
    SLRequire(data.length<=32*1024*1024,@"json.limit",@"JSON document exceeds 32 MiB");
    SLDecodeUTF8(data);
    SLJSONReader *reader=[SLJSONReader new]; reader.data=data;
    id result=[reader value:0]; [reader space];
    SLRequire(reader.at==data.length,@"json.syntax",@"Trailing bytes after JSON document"); return result;
}
NSData *SLJSONData(id object) {
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys|NSJSONWritingFragmentsAllowed error:&error];
    SLRequire(data && !error,@"json.encode",@"Value cannot be encoded as JSON"); return data;
}
NSString *SLJSONString(id object) { return SLDecodeUTF8(SLJSONData(object)); }
