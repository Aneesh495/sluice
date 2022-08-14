#import "SLPrivacy.h"
#import "SLTarget.h"
#import "SLBytes.h"
#import "SLJSON.h"
#import "SLError.h"
@implementation SLPrivacy {
    NSSet *_headers;
    NSSet *_query;
    NSSet *_jsonKeys;
}
static NSSet *Names(NSArray *defaults, id configured, NSString *field) {
    NSMutableSet *names=[NSMutableSet setWithArray:defaults];
    if (configured) for (id name in SLArray(configured,256,field)) {
        NSString *s=SLString(name,256,field); SLRequire(s.length>0,@"privacy.name",@"Privacy field name cannot be empty");
        [names addObject:s.lowercaseString];
    }
    return [names copy];
}
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self=[super init])) {
        SLObject(document,@"privacy"); SLKeys(document,@[@"version",@"bodies",@"headers",@"query",@"jsonKeys"],@[@"version",@"bodies"],@"privacy");
        SLInteger(document[@"version"],1,1,@"version"); _bodyMode=[SLString(document[@"bodies"],16,@"bodies") copy];
        SLRequire([@[@"omit",@"json"] containsObject:_bodyMode],@"privacy.mode",@"bodies must be omit or json");
        _headers=Names(@[@"authorization",@"proxy-authorization",@"cookie",@"set-cookie",@"x-api-key"],document[@"headers"],@"headers");
        _query=Names(@[@"token",@"access_token",@"password",@"secret",@"key",@"api_key",@"authorization"],document[@"query"],@"query");
        _jsonKeys=Names(@[@"password",@"secret",@"token",@"access_token",@"api_key",@"authorization"],document[@"jsonKeys"],@"jsonKeys");
        _document=SLJSONRead(SLJSONData(document)); _digest=SLSHA256(SLJSONData(_document));
    } return self;
}
+ (instancetype)metadataOnly { return [[self alloc] initWithDocument:@{@"version":@1,@"bodies":@"omit"}]; }
- (NSString *)target:(NSString *)target {
    SLValidateTarget(target); NSRange q=[target rangeOfString:@"?"];
    if (q.location==NSNotFound) return target;
    NSMutableArray *parts=[NSMutableArray array];
    for (NSString *part in [[target substringFromIndex:q.location+1] componentsSeparatedByString:@"&"]) {
        NSRange equals=[part rangeOfString:@"="]; NSString *key=equals.location==NSNotFound?part:[part substringToIndex:equals.location];
        NSString *decoded=[[key stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
        SLRequire(decoded!=nil,@"privacy.query",@"Query parameter name has invalid UTF-8 escapes");
        [parts addObject:[_query containsObject:decoded.lowercaseString] ? [key stringByAppendingString:@"=%5Bredacted%5D"] : part];
    }
    return [NSString stringWithFormat:@"%@?%@",[target substringToIndex:q.location],[parts componentsJoinedByString:@"&"]];
}
- (SLHeaders *)headers:(SLHeaders *)headers {
    NSMutableArray *pairs=[NSMutableArray array];
    for (NSArray *pair in [[headers endToEnd] without:[NSSet setWithArray:@[@"content-length"]]].pairs)
        [pairs addObject:@[pair[0],[_headers containsObject:[pair[0] lowercaseString]] ? @"[redacted]" : pair[1]]];
    return [[SLHeaders alloc] initWithPairs:pairs];
}
- (id)sanitizeJSON:(id)value {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result=[NSMutableDictionary dictionary];
        for (NSString *key in value) result[key]=[_jsonKeys containsObject:key.lowercaseString] ? @"[redacted]" : [self sanitizeJSON:value[key]];
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result=[NSMutableArray array]; for (id item in value) [result addObject:[self sanitizeJSON:item]]; return result;
    }
    return value;
}
- (NSDictionary *)message:(SLMessage *)message {
    SLHeaders *headers=[self headers:message.headers]; NSData *body=NSData.data;
    NSString *state=message.body.length?@"omitted":@"empty";
    NSString *type=[[[message.headers first:@"Content-Type"] componentsSeparatedByString:@";"].firstObject.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *encoding=[message.headers first:@"Content-Encoding"];
    if (message.body.length && [self.bodyMode isEqual:@"json"] && ([type isEqual:@"application/json"] || [type hasSuffix:@"+json"]) && (!encoding || [encoding.lowercaseString isEqual:@"identity"])) {
        @try { body=SLJSONData([self sanitizeJSON:SLJSONRead(message.body)]); state=@"json"; }
        @catch (SLError *error) { /* Invalid or over-budget JSON stays omitted. */ }
    }
    if ([state isEqual:@"json"]) headers=[headers without:[NSSet setWithArray:@[@"etag",@"content-md5",@"digest",@"content-encoding"]]];
    NSMutableDictionary *result=[@{@"headers":headers.pairs,@"body":[body base64EncodedStringWithOptions:0],@"bodyState":state,@"originalBytes":@(message.body.length)} mutableCopy];
    if (message.request) { result[@"method"]=message.method; result[@"target"]=[self target:message.target]; }
    else { result[@"status"]=@(message.status); result[@"reason"]=message.reason; }
    return [result copy];
}
@end
SLMessage *SLMessageFromDocument(NSDictionary *document, BOOL request) {
    SLObject(document,@"message");
    SLKeys(document,request?@[@"headers",@"body",@"bodyState",@"originalBytes",@"method",@"target"]:@[@"headers",@"body",@"bodyState",@"originalBytes",@"status",@"reason"],request?@[@"headers",@"body",@"bodyState",@"originalBytes",@"method",@"target"]:@[@"headers",@"body",@"bodyState",@"originalBytes",@"status",@"reason"],@"message");
    NSString *state=SLString(document[@"bodyState"],16,@"bodyState");
    SLRequire([@[@"json",@"omitted",@"empty"] containsObject:state],@"fixture.body",@"Unknown body state");
    SLInteger(document[@"originalBytes"],0,8*1024*1024,@"originalBytes");
    SLMessage *m=[SLMessage new]; m.request=request; m.headers=[[SLHeaders alloc] initWithPairs:document[@"headers"]];
    m.body=[[NSData alloc] initWithBase64EncodedString:SLString(document[@"body"],12*1024*1024,@"body") options:0];
    SLRequire(m.body!=nil && m.body.length<=8*1024*1024,@"fixture.body",@"Invalid or oversized base64 body");
    SLRequire([state isEqual:@"json"] || !m.body.length,@"fixture.body",@"Omitted and empty bodies must contain no bytes");
    if ([state isEqual:@"json"]) SLJSONRead(m.body);
    if (request) { m.method=SLString(document[@"method"],32,@"method"); SLRequire(SLToken(m.method),@"fixture.method",@"Invalid method"); m.target=SLValidateTarget(SLString(document[@"target"],8192,@"target")); }
    else { m.status=(NSInteger)SLInteger(document[@"status"],200,599,@"status"); m.reason=SLString(document[@"reason"],1024,@"reason"); SLRequire(SLFieldValue(m.reason),@"fixture.reason",@"Invalid status reason"); }
    return m;
}
NSString *SLRequestIdentity(NSDictionary *request) {
    SLMessage *m=SLMessageFromDocument(request,YES);
    // Host is deliberately absent: the offline listener replaces the origin.
    return SLSHA256(SLJSONData(@[@"sluice.request.v1",m.method,m.target,request[@"bodyState"],SLSHA256(m.body),[m.headers values:@"Content-Type"],[m.headers values:@"Accept"]]));
}
