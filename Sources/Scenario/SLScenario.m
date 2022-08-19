#import "SLScenario.h"
#import "SLRandom.h"
#import "SLBytes.h"
#import "SLJSON.h"
#import "SLError.h"
@implementation SLRule
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self=[super init])) {
        document=SLJSONRead(SLJSONData(document));
        SLObject(document,@"rule"); SLKeys(document,@[@"id",@"match",@"action",@"after",@"every",@"limit",@"chancePermille"],@[@"id",@"match",@"action"],@"rule");
        _identifier=[SLString(document[@"id"],128,@"rule.id") copy];
        SLRequire(SLToken(_identifier),@"scenario.id",@"Rule id must be a nonempty token");
        _match=[[SLMatch alloc] initWithDocument:document[@"match"]];
        _action=[[SLAction alloc] initWithDocument:document[@"action"]];
        _after=(NSUInteger)SLInteger(document[@"after"] ?: @0,0,1000000000,@"after");
        _every=(NSUInteger)SLInteger(document[@"every"] ?: @1,1,1000000000,@"every");
        _limit=(NSUInteger)SLInteger(document[@"limit"] ?: @0,0,1000000000,@"limit");
        _chance=(NSUInteger)SLInteger(document[@"chancePermille"] ?: @1000,0,1000,@"chancePermille");
    } return self;
}
- (BOOL)selectsOccurrence:(uint64_t)occurrence identity:(NSString *)identity seed:(uint64_t)seed {
    if (occurrence<=self.after) return NO;
    uint64_t relative=occurrence-self.after-1;
    if (relative%self.every || (self.limit && relative/self.every>=self.limit)) return NO;
    return SLDraw(seed,self.identifier,identity,occurrence,@"chance")%1000<self.chance;
}
@end
@implementation SLScenario
- (instancetype)initWithDocument:(NSDictionary *)document {
    if ((self=[super init])) {
        document=SLJSONRead(SLJSONData(document));
        SLObject(document,@"scenario"); SLKeys(document,@[@"version",@"name",@"seed",@"rules"],@[@"version",@"name",@"seed",@"rules"],@"scenario");
        SLInteger(document[@"version"],1,1,@"version"); _name=[SLString(document[@"name"],256,@"name") copy];
        SLRequire(_name.length>0,@"scenario.name",@"Scenario name cannot be empty");
        _seed=(uint64_t)SLInteger(document[@"seed"],0,INT64_MAX,@"seed");
        NSMutableArray *rules=[NSMutableArray array]; NSMutableSet *ids=[NSMutableSet set];
        for (id item in SLArray(document[@"rules"],256,@"rules")) {
            SLRule *rule=[[SLRule alloc] initWithDocument:item];
            SLRequire(![ids containsObject:rule.identifier],@"scenario.duplicate",@"Rule ids must be unique");
            [ids addObject:rule.identifier]; [rules addObject:rule];
        }
        _rules=[rules copy];
        // Deep copy through the strict reader prevents callers from mutating
        // nested rule dictionaries after validation.
        _document=SLJSONRead(SLJSONData(document)); _digest=SLSHA256(SLJSONData(_document));
    } return self;
}
+ (instancetype)passthrough { return [[self alloc] initWithDocument:@{@"version":@1,@"name":@"passthrough",@"seed":@0,@"rules":@[]}]; }
- (SLRule *)ruleFor:(SLMessage *)request identity:(NSString *)identity occurrence:(uint64_t)occurrence {
    SLRequire(occurrence>0,@"scenario.occurrence",@"Occurrences start at one");
    for (SLRule *rule in self.rules) if ([rule.match matches:request] && [rule selectsOccurrence:occurrence identity:identity seed:self.seed]) return rule;
    return nil;
}
@end
