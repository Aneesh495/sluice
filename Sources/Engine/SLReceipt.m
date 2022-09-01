#import "SLReceipt.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
NSDictionary *SLMakeReceipt(NSString *session, NSString *mode, NSString *identity, uint64_t occurrence, NSString *fixture, NSDictionary *plan, NSUInteger acceptedBytes, uint64_t elapsedUS, NSString *outcome, NSString *errorCode) {
    NSMutableDictionary *r=[@{@"version":@1,@"id":NSUUID.UUID.UUIDString.lowercaseString,@"createdMs":@((int64_t)(NSDate.date.timeIntervalSince1970*1000)),@"session":session,@"mode":mode,@"identity":identity,@"occurrence":@(occurrence),@"acceptedBytes":@(acceptedBytes),@"elapsedUs":@(elapsedUS),@"outcome":outcome} mutableCopy];
    if (fixture) r[@"fixture"]=fixture; if (plan) r[@"plan"]=plan; if (errorCode) r[@"error"]=errorCode;
    SLValidateReceipt(r); return SLJSONRead(SLJSONData(r));
}
void SLValidateReceipt(NSDictionary *r) {
    SLObject(r,@"receipt"); SLKeys(r,@[@"version",@"id",@"createdMs",@"session",@"mode",@"identity",@"occurrence",@"acceptedBytes",@"elapsedUs",@"outcome",@"fixture",@"plan",@"error"],@[@"version",@"id",@"createdMs",@"session",@"mode",@"identity",@"occurrence",@"acceptedBytes",@"elapsedUs",@"outcome"],@"receipt");
    SLInteger(r[@"version"],1,1,@"receipt.version");
    for (NSString *key in @[@"id",@"session"]) SLRequire([[NSUUID alloc] initWithUUIDString:SLString(r[key],64,key)]!=nil,@"receipt.id",@"Receipt and session ids must be UUIDs");
    SLInteger(r[@"createdMs"],0,INT64_MAX,@"createdMs");
    SLRequire([@[@"record",@"replay"] containsObject:r[@"mode"]],@"receipt.mode",@"Invalid receipt mode");
    SLString(r[@"identity"],64,@"identity"); SLInteger(r[@"occurrence"],0,INT64_MAX,@"occurrence");
    int64_t accepted=SLInteger(r[@"acceptedBytes"],0,9*1024*1024,@"acceptedBytes");
    SLInteger(r[@"elapsedUs"],0,INT64_MAX,@"elapsedUs");
    SLRequire([@[@"complete",@"client-closed",@"upstream-error",@"request-error",@"timeout",@"shutdown",@"engine-error"] containsObject:r[@"outcome"]],@"receipt.outcome",@"Invalid receipt outcome");
    if (r[@"fixture"]) SLRequire([[NSUUID alloc] initWithUUIDString:SLString(r[@"fixture"],64,@"fixture")]!=nil,@"receipt.id",@"Invalid fixture id");
    if (r[@"error"]) SLString(r[@"error"],128,@"error");
    if (r[@"plan"]) {
        NSDictionary *plan=SLObject(r[@"plan"],@"plan");
        int64_t wire=SLInteger(plan[@"wireBytes"],0,9*1024*1024,@"wireBytes");
        SLRequire(accepted<=wire,@"receipt.bytes",@"Accepted bytes exceed planned wire bytes");
        SLRequire([plan[@"identity"] isEqual:r[@"identity"]] && [plan[@"occurrence"] isEqual:r[@"occurrence"]],@"receipt.identity",@"Plan identity disagrees with receipt");
    }
}
