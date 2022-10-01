#import <Foundation/Foundation.h>
#import "SLArguments.h"
#import "SLReactor.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
#import "SLBundle.h"
#import "SLHAR.h"
#import "SLDiff.h"
#import "SLReport.h"
#import <dispatch/dispatch.h>
#import <signal.h>
#import <sqlite3.h>
static void Print(id object) { puts(SLJSONString(object).UTF8String); fflush(stdout); }
static id Document(NSString *path) { return SLJSONRead(SLReadFile(path,32*1024*1024)); }
static void Help(void) {
    puts("sluice 0.1.0 | HTTP dependency outage workbench\n\n"
         "record   --workspace DIR --upstream http://HOST:PORT [--port 8080]\n"
         "replay   --workspace DIR [--port 8080] [--fixture UUID]\n"
         "         [--privacy FILE] [--scenario FILE]\n"
         "fixtures --workspace DIR [--id UUID]\n"
         "receipts --workspace DIR [--limit 100]\n"
         "plan     --workspace DIR --fixture UUID --scenario FILE [--occurrence 1]\n"
         "validate --scenario FILE | --privacy FILE\n"
         "check    --workspace DIR\n"
         "export   --workspace DIR --output FILE [--fixture UUID]\n"
         "import   --workspace DIR --input FILE\n"
         "har      --workspace DIR --input FILE [--privacy FILE]\n"
         "diff     --workspace DIR --before UUID --after UUID\n"
         "report   --workspace DIR [--session UUID]\n"
         "doctor\n\n"
         "record and replay bind only 127.0.0.1. Use port 0 for an ephemeral port.\n"
         "Recording omits bodies by default. Opt into sanitized JSON with a privacy file.\n"
         "SIGINT and SIGTERM drain receipts and stop the listener. Output is JSON.");
}
int main(int argc, const char **argv) {
    @autoreleasepool { @try {
        NSMutableArray *raw=[NSMutableArray array]; for (int i=1;i<argc;i++) [raw addObject:@(argv[i])];
        if (!raw.count || [@[@"help",@"--help",@"--version"] containsObject:raw[0]]) { Help(); return 0; }
        NSString *command=raw[0]; [raw removeObjectAtIndex:0];
        NSDictionary *schemas=@{@"record":@[@"workspace",@"upstream",@"port",@"privacy",@"scenario"],@"replay":@[@"workspace",@"port",@"privacy",@"scenario",@"fixture"],@"fixtures":@[@"workspace",@"id"],@"receipts":@[@"workspace",@"limit"],@"plan":@[@"workspace",@"fixture",@"scenario",@"occurrence"],@"validate":@[@"scenario",@"privacy"],@"check":@[@"workspace"],@"doctor":@[],@"export":@[@"workspace",@"output",@"fixture"],@"import":@[@"workspace",@"input"],@"har":@[@"workspace",@"input",@"privacy"],@"diff":@[@"workspace",@"before",@"after"],@"report":@[@"workspace",@"session"]};
        SLRequire(schemas[command]!=nil,@"cli.command",@"Unknown command; run sluice --help");
        SLArguments *a=[[SLArguments alloc] initWithArguments:raw values:schemas[command] flags:@[@"help"]];
        if ([a has:@"help"]) { Help(); return 0; }
        SLRequire(!a.operands.count,@"cli.operands",@"This command does not accept positional operands");
        if ([command isEqual:@"doctor"]) {
            Print(@{@"version":@"0.1.0",@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"sqlite":@(sqlite3_libversion()),@"listener":@"127.0.0.1",@"tlsInterception":@NO}); return 0;
        }
        if ([command isEqual:@"validate"]) {
            SLRequire([a has:@"scenario"] || [a has:@"privacy"],@"cli.required",@"Provide --scenario or --privacy");
            NSMutableDictionary *result=[NSMutableDictionary dictionary];
            if ([a has:@"scenario"]) { SLScenario *s=[[SLScenario alloc] initWithDocument:Document([a required:@"scenario"])]; result[@"scenario"]=@{@"name":s.name,@"sha256":s.digest,@"rules":@(s.rules.count)}; }
            if ([a has:@"privacy"]) { SLPrivacy *p=[[SLPrivacy alloc] initWithDocument:Document([a required:@"privacy"])]; result[@"privacy"]=@{@"sha256":p.digest,@"bodies":p.bodyMode}; }
            Print(result); return 0;
        }
        SLStore *store=[[SLStore alloc] initWithDirectory:[a required:@"workspace"]];
        if ([command isEqual:@"export"]) {
            NSArray *fixtures=store.fixtures;
            if ([a has:@"fixture"]) { SLFixture *f=[store fixture:[a required:@"fixture"]]; SLRequire(f!=nil,@"fixture.missing",@"No fixture has that id"); fixtures=@[f]; }
            NSData *data=SLBundleEncode(fixtures); SLAtomicWrite(data,[a required:@"output"]);
            Print(@{@"fixtures":@(fixtures.count),@"bytes":@(data.length),@"sha256":SLSHA256(data)});
        } else if ([command isEqual:@"import"] || [command isEqual:@"har"]) {
            NSData *data=SLReadFile([a required:@"input"],32*1024*1024);
            SLPrivacy *privacy=[a has:@"privacy"] ? [[SLPrivacy alloc] initWithDocument:Document([a required:@"privacy"])] : SLPrivacy.metadataOnly;
            NSArray *fixtures=[command isEqual:@"har"] ? SLHARImport(data,privacy) : SLBundleDecode(data);
            [store importFixtures:fixtures]; Print(@{@"validated":@(fixtures.count),@"workspace":store.statistics});
        } else if ([command isEqual:@"diff"]) {
            SLFixture *before=[store fixture:[a required:@"before"]], *after=[store fixture:[a required:@"after"]];
            SLRequire(before && after,@"fixture.missing",@"Both fixture ids must exist"); Print(SLFixtureDiff(before,after));
        } else if ([command isEqual:@"report"]) {
            NSArray *receipts=[store receipts:100000];
            if ([a has:@"session"]) { NSString *session=[a required:@"session"]; receipts=[receipts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, NSDictionary *bindings) { return [r[@"session"] isEqual:session]; }]]; }
            Print(SLReceiptReport(receipts));
        } else if ([command isEqual:@"fixtures"]) {
            if ([a has:@"id"]) { SLFixture *f=[store fixture:[a required:@"id"]]; SLRequire(f!=nil,@"fixture.missing",@"No fixture has that id"); Print(f.document); }
            else { NSMutableArray *list=[NSMutableArray array]; for (SLFixture *f in store.fixtures) [list addObject:@{@"id":f.identifier,@"identity":f.identity,@"method":f.request.method,@"target":f.request.target,@"status":@(f.response.status),@"replayable":@(f.replayable),@"bodyBytes":@(f.response.body.length)}]; Print(list); }
        } else if ([command isEqual:@"receipts"]) Print([store receipts:(NSUInteger)[a integer:@"limit" fallback:100 minimum:1 maximum:100000]]);
        else if ([command isEqual:@"check"]) { [store checkIntegrity]; Print(store.statistics); }
        else if ([command isEqual:@"plan"]) {
            SLFixture *fixture=[store fixture:[a required:@"fixture"]]; SLRequire(fixture!=nil,@"fixture.missing",@"No fixture has that id");
            SLScenario *scenario=[[SLScenario alloc] initWithDocument:Document([a required:@"scenario"])];
            uint64_t occurrence=(uint64_t)[a integer:@"occurrence" fallback:1 minimum:1 maximum:INT64_MAX];
            SLRule *rule=[scenario ruleFor:fixture.request identity:fixture.identity occurrence:occurrence];
            Print([[SLDeliveryPlan alloc] initResponse:fixture.response request:fixture.request rule:rule scenario:scenario identity:fixture.identity occurrence:occurrence].summary);
        } else {
            SLPrivacy *privacy=[a has:@"privacy"] ? [[SLPrivacy alloc] initWithDocument:Document([a required:@"privacy"])] : SLPrivacy.metadataOnly;
            SLScenario *scenario=[a has:@"scenario"] ? [[SLScenario alloc] initWithDocument:Document([a required:@"scenario"])] : SLScenario.passthrough;
            SLSession *session=[[SLSession alloc] initMode:command store:store privacy:privacy scenario:scenario fixture:[a value:@"fixture"]];
            SLEndpoint *endpoint=[command isEqual:@"record"] ? [SLEndpoint parse:[a required:@"upstream"]] : nil;
            SLReactor *reactor=[[SLReactor alloc] initSession:session upstream:endpoint port:(uint16_t)[a integer:@"port" fallback:8080 minimum:0 maximum:65535]];
            signal(SIGINT,SIG_IGN); signal(SIGTERM,SIG_IGN);
            dispatch_source_t interrupt=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0));
            dispatch_source_t terminate=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0));
            dispatch_source_set_event_handler(interrupt,^{ [reactor stop]; }); dispatch_source_set_event_handler(terminate,^{ [reactor stop]; });
            dispatch_resume(interrupt); dispatch_resume(terminate);
            [reactor runReady:^(uint16_t port) { Print(@{@"event":@"ready",@"host":@"127.0.0.1",@"port":@(port),@"session":session.identifier,@"mode":command,@"scenario":scenario.digest,@"privacy":privacy.digest}); }];
            dispatch_source_cancel(interrupt); dispatch_source_cancel(terminate);
            SLRequire(!reactor.fatalError,@"reactor.storage",reactor.fatalError ?: @"Reactor failed");
            Print(@{@"event":@"stopped",@"completed":@(reactor.completedConnections)});
        }
        return 0;
    } @catch (SLError *error) {
        fprintf(stderr,"%s\n",SLJSONString(@{@"error":error.code,@"message":error.reason ?: @"Operation failed"}).UTF8String); return 2;
    } @catch (NSException *error) {
        fprintf(stderr,"%s\n",SLJSONString(@{@"error":@"internal.exception",@"message":error.name}).UTF8String); return 3;
    }}
}
