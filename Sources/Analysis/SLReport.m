#import "SLReport.h"
#import "SLReceipt.h"
static void Increment(NSMutableDictionary *counts, NSString *key) {
    counts[key] = @([counts[key] unsignedLongLongValue] + 1);
}
static NSNumber *Percentile(NSArray<NSNumber *> *sorted, NSUInteger percentage) {
    if (!sorted.count)
        return @0;
    NSUInteger rank = (sorted.count * percentage + 99) / 100;
    return sorted[MAX((NSUInteger)1, rank) - 1];
}
NSDictionary *SLReceiptReport(NSArray *receipts) {
    NSMutableDictionary *outcomes = [NSMutableDictionary dictionary],
                        *status = [NSMutableDictionary dictionary],
                        *errors = [NSMutableDictionary dictionary],
                        *sessions = [NSMutableDictionary dictionary];
    NSMutableArray *elapsed = [NSMutableArray array];
    uint64_t bytes = 0;
    NSUInteger truncated = 0, disconnected = 0, planned = 0;
    for (NSDictionary *receipt in receipts) {
        SLValidateReceipt(receipt);
        Increment(outcomes, receipt[@"outcome"]);
        Increment(sessions, receipt[@"session"]);
        [elapsed addObject:receipt[@"elapsedUs"]];
        bytes += [receipt[@"acceptedBytes"] unsignedLongLongValue];
        if (receipt[@"error"])
            Increment(errors, receipt[@"error"]);
        NSDictionary *plan = receipt[@"plan"];
        if (plan) {
            planned++;
            Increment(status, [plan[@"status"] stringValue]);
            truncated += [plan[@"truncated"] boolValue];
            disconnected += [plan[@"disconnect"] boolValue];
        }
    }
    NSArray *sorted = [elapsed sortedArrayUsingSelector:@selector(compare:)];
    return @{
        @"receipts" : @(receipts.count),
        @"sessions" : sessions,
        @"outcomes" : outcomes,
        @"status" : status,
        @"errors" : errors,
        @"socketAcceptedBytes" : @(bytes),
        @"plannedDeliveries" : @(planned),
        @"plannedTruncations" : @(truncated),
        @"plannedDisconnects" : @(disconnected),
        @"elapsedUs" : @{
            @"min" : sorted.firstObject ?: @0,
            @"p50" : Percentile(sorted, 50),
            @"p95" : Percentile(sorted, 95),
            @"max" : sorted.lastObject ?: @0
        },
        @"interpretation" : @"Delivery completion is a transport observation. It does not "
                            @"establish client application success."
    };
}
