#import "SLTarget.h"
#import "SLBytes.h"
#import "SLError.h"
NSString *SLValidateTarget(NSString *target) {
    NSData *data=[target dataUsingEncoding:NSASCIIStringEncoding];
    SLRequire(data.length>0 && data.length<=8192 && [target hasPrefix:@"/"],@"http.target",@"Only bounded origin-form request targets are supported");
    const uint8_t *p=data.bytes;
    for (NSUInteger i=0;i<data.length;i++) {
        SLRequire(p[i]>32 && p[i]<127 && p[i]!='#' && p[i]!='\\',@"http.target",@"Invalid byte in request target");
        if (p[i]=='%') {
            SLRequire(i+2<data.length && isxdigit(p[i+1]) && isxdigit(p[i+2]),@"http.target",@"Invalid percent escape in request target"); i+=2;
        }
    }
    return [target copy];
}
NSString *SLTargetPath(NSString *target) {
    NSRange q=[target rangeOfString:@"?"]; return q.location==NSNotFound ? target : [target substringToIndex:q.location];
}
@implementation SLEndpoint
+ (instancetype)parse:(NSString *)url {
    SLString(url,4096,@"upstream"); NSURLComponents *c=[NSURLComponents componentsWithString:url];
    SLRequire(c && [c.scheme.lowercaseString isEqual:@"http"] && c.host.length && !c.user && !c.password && !c.query && !c.fragment && (!c.path.length || [c.path isEqual:@"/"]),
              @"upstream.url",@"Upstream must be http://host[:port] with no path, credentials, query, or fragment");
    SLEndpoint *endpoint=[SLEndpoint new]; endpoint->_host=[c.host copy];
    if ([endpoint->_host hasPrefix:@"["] && [endpoint->_host hasSuffix:@"]"]) endpoint->_host=[endpoint->_host substringWithRange:NSMakeRange(1,endpoint->_host.length-2)];
    endpoint->_port=(uint16_t)(c.port ? SLInteger(c.port,1,65535,@"upstream port") : 80);
    NSString *host=[endpoint.host containsString:@":"] ? [NSString stringWithFormat:@"[%@]",endpoint.host] : endpoint.host;
    endpoint->_authority=[NSString stringWithFormat:@"%@:%u",host,endpoint.port]; return endpoint;
}
@end
