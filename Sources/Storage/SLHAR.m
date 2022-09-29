#import "SLHAR.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLTarget.h"
#import "SLError.h"
static SLHeaders *Headers(id input) {
    NSMutableArray *pairs=[NSMutableArray array];
    for (id item in SLArray(input,128,@"HAR headers")) {
        NSDictionary *header=SLObject(item,@"HAR header");
        [pairs addObject:@[SLString(header[@"name"],256,@"header.name"),SLString(header[@"value"],8192,@"header.value")]];
    }
    return [[SLHeaders alloc] initWithPairs:pairs];
}
static NSData *Content(NSDictionary *content, BOOL request) {
    id text=content[@"text"];
    if (!text) {
        id size=content[request?@"bodySize":@"size"];
        SLRequire(!size || SLInteger(size,-1,8*1024*1024,@"HAR body size")==0,@"har.body",@"HAR body is unavailable; refusing to invent an empty response");
        return NSData.data;
    }
    NSString *s=SLString(text,12*1024*1024,@"HAR body text");
    NSString *encoding=content[@"encoding"];
    SLRequire(!encoding || [encoding isEqual:@"base64"],@"har.encoding",@"Unsupported HAR content encoding");
    NSData *body=encoding ? [[NSData alloc] initWithBase64EncodedString:s options:0] : SLUTF8(s);
    SLRequire(body && body.length<=8*1024*1024,@"har.body",@"HAR body is invalid or exceeds 8 MiB"); return body;
}
NSArray *SLHARImport(NSData *data, SLPrivacy *privacy) {
    NSDictionary *root=SLObject(SLJSONRead(data),@"HAR"); NSDictionary *log=SLObject(root[@"log"],@"HAR log");
    SLRequire([log[@"version"] isEqual:@"1.2"],@"har.version",@"Only HAR 1.2 is supported");
    NSMutableArray *fixtures=[NSMutableArray array];
    for (id item in SLArray(log[@"entries"],1000,@"HAR entries")) {
        NSDictionary *entry=SLObject(item,@"HAR entry");
        NSDictionary *req=SLObject(entry[@"request"],@"HAR request"), *res=SLObject(entry[@"response"],@"HAR response");
        NSURLComponents *url=[NSURLComponents componentsWithString:SLString(req[@"url"],16384,@"HAR URL")];
        SLRequire(url.host.length && [@[@"http",@"https"] containsObject:url.scheme.lowercaseString] && !url.user && !url.password && !url.fragment,@"har.url",@"HAR request URL must be HTTP(S) without userinfo or fragments");
        SLMessage *request=[SLMessage new]; request.request=YES; request.method=SLString(req[@"method"],32,@"HAR method");
        SLRequire(SLToken(request.method),@"har.method",@"Invalid HAR method");
        NSString *target=url.percentEncodedPath.length?url.percentEncodedPath:@"/";
        if (url.percentEncodedQuery) target=[target stringByAppendingFormat:@"?%@",url.percentEncodedQuery]; request.target=SLValidateTarget(target);
        request.headers=Headers(req[@"headers"]);
        if (req[@"postData"]) {
            NSDictionary *post=SLObject(req[@"postData"],@"HAR postData");
            SLRequire(post[@"text"]!=nil,@"har.body",@"HAR form parameters without original body text are unsupported");
            request.body=Content(post,YES);
            if (![request.headers first:@"Content-Type"] && post[@"mimeType"]) request.headers=[request.headers setting:@"Content-Type" value:SLString(post[@"mimeType"],256,@"mimeType")];
        } else if (req[@"bodySize"]) SLRequire(SLInteger(req[@"bodySize"],-1,8*1024*1024,@"request.bodySize")<=0,@"har.body",@"HAR request body bytes are missing");
        NSDictionary *content=SLObject(res[@"content"],@"HAR response content");
        SLMessage *response=[SLMessage response:(NSInteger)SLInteger(res[@"status"],200,599,@"HAR status") body:Content(content,NO) contentType:SLString(content[@"mimeType"] ?: @"application/octet-stream",256,@"mimeType")];
        response.reason=SLString(res[@"statusText"] ?: @"Response",1024,@"HAR statusText"); response.headers=Headers(res[@"headers"]);
        if (![response.headers first:@"Content-Type"]) response.headers=[response.headers setting:@"Content-Type" value:content[@"mimeType"] ?: @"application/octet-stream"];
        // HAR content.text is the decoded entity, even when the original wire
        // used compression. Retaining Content-Encoding would double-decode it.
        response.headers=[response.headers without:[NSSet setWithArray:@[@"content-encoding",@"content-length",@"transfer-encoding"]]];
        [fixtures addObject:[SLFixture captureRequest:request response:response privacy:privacy]];
    }
    return [fixtures copy];
}
