#import "SLInspector.h"
#import "SLTheme.h"
#import "SLTimelineView.h"
#import "SLDeliveryPlan.h"
#import "SLJSON.h"
@implementation SLInspector {
    NSTextField *_title;
    NSTextField *_subtitle;
    NSSegmentedControl *_tabs;
    SLTimelineView *_timeline;
    NSTextView *_text;
    NSArray *_documents;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = SLTheme.background.CGColor;
        _title = [SLTheme label:@"Inspect an exchange" size:20 weight:NSFontWeightSemibold];
        _subtitle = [SLTheme label:@"Request, response, and the bytes in between."
                              size:11
                            weight:NSFontWeightRegular];
        _subtitle.textColor = SLTheme.muted;
        _tabs =
            [NSSegmentedControl segmentedControlWithLabels:@[ @"Overview", @"Request", @"Response" ]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                    target:self
                                                    action:@selector(changeTab:)];
        _tabs.selectedSegment = 0;
        _timeline = [[SLTimelineView alloc] initWithFrame:NSZeroRect];
        NSScrollView *scroll = [NSScrollView new];
        scroll.hasVerticalScroller = YES;
        scroll.hasHorizontalScroller = NO;
        scroll.drawsBackground = NO;
        scroll.borderType = NSNoBorder;
        _text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        _text.editable = NO;
        _text.selectable = YES;
        _text.richText = NO;
        _text.font = [SLTheme mono:11];
        _text.textColor = NSColor.labelColor;
        _text.backgroundColor = SLTheme.background;
        _text.textContainerInset = NSMakeSize(10, 14);
        _text.autoresizingMask = NSViewWidthSizable;
        _text.verticallyResizable = YES;
        _text.horizontallyResizable = NO;
        _text.textContainer.widthTracksTextView = YES;
        _text.accessibilityLabel = @"Exchange details";
        scroll.documentView = _text;
        NSArray *views = @[ _title, _subtitle, _tabs, _timeline, scroll ];
        for (NSView *v in views) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_title.topAnchor constraintEqualToAnchor:self.topAnchor constant:22],
            [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [_subtitle.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:7],
            [_subtitle.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_subtitle.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
            [_tabs.topAnchor constraintEqualToAnchor:_subtitle.bottomAnchor constant:18],
            [_tabs.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_timeline.topAnchor constraintEqualToAnchor:_tabs.bottomAnchor constant:18],
            [_timeline.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_timeline.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
            [_timeline.heightAnchor constraintEqualToConstant:180],
            [scroll.topAnchor constraintEqualToAnchor:_timeline.bottomAnchor constant:8],
            [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10]
        ]];
        [self showEmpty];
    }
    return self;
}
static NSDictionary *Present(NSDictionary *message) {
    NSMutableDictionary *result = [message mutableCopy];
    [result removeObjectForKey:@"body"];
    if ([message[@"bodyState"] isEqual:@"json"]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:message[@"body"] options:0];
        result[@"bodyJSON"] = SLJSONRead(data);
    }
    return result;
}
- (void)changeTab:(id)sender {
    if (!_documents.count)
        return;
    NSInteger selected = MAX((NSInteger)0, _tabs.selectedSegment);
    id document = _documents[MIN((NSUInteger)selected, _documents.count - 1)];
    NSData *data =
        [NSJSONSerialization dataWithJSONObject:document
                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                          error:NULL];
    _text.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                       ?: @"Unable to display document";
    [_text scrollRangeToVisible:NSMakeRange(0, 0)];
}
- (void)showEmpty {
    _title.stringValue = @"Ready for the unexpected";
    _subtitle.stringValue = @"Record a dependency, then rehearse its next bad day.";
    _timeline.plan = nil;
    _timeline.acceptedBytes = nil;
    _documents = @[ @{
        @"start" : @"Record an HTTP dependency, or import a fixture bundle or HAR archive.",
        @"next" : @"Select a fixture to inspect it. Load a scenario and start offline replay to "
                  @"rehearse a failure.",
        @"privacy" : @"Bodies are omitted until you select a JSON privacy policy."
    } ];
    _tabs.enabled = NO;
    [self changeTab:nil];
}
- (void)showFixture:(SLFixture *)fixture scenario:(SLScenario *)scenario {
    _title.stringValue = [NSString
        stringWithFormat:@"%@  %ld", fixture.request.method, (long)fixture.response.status];
    _subtitle.stringValue = fixture.request.target;
    _tabs.enabled = YES;
    SLRule *rule = [scenario ruleFor:fixture.request identity:fixture.identity occurrence:1];
    SLDeliveryPlan *plan = [[SLDeliveryPlan alloc] initResponse:fixture.response
                                                        request:fixture.request
                                                           rule:rule
                                                       scenario:scenario
                                                       identity:fixture.identity
                                                     occurrence:1];
    _timeline.plan = plan.summary;
    _timeline.acceptedBytes = nil;
    _documents = @[
        @{
            @"fixture" : fixture.identifier,
            @"identity" : fixture.identity,
            @"replayable" : @(fixture.replayable),
            @"planAtOccurrenceOne" : plan.summary
        },
        Present(fixture.document[@"request"]), Present(fixture.document[@"response"])
    ];
    [self changeTab:nil];
}
- (void)showReceipt:(NSDictionary *)receipt {
    _title.stringValue = [receipt[@"outcome"] description];
    _subtitle.stringValue =
        [NSString stringWithFormat:@"Occurrence %@  ·  %@ ms  ·  %@", receipt[@"occurrence"],
                                   @([receipt[@"elapsedUs"] doubleValue] / 1000), receipt[@"mode"]];
    _tabs.enabled = NO;
    _timeline.plan = receipt[@"plan"];
    _timeline.acceptedBytes = receipt[@"acceptedBytes"];
    _documents = @[ receipt ];
    [self changeTab:nil];
}
- (void)showOverview:(NSDictionary *)overview {
    _title.stringValue = @"Session overview";
    _subtitle.stringValue = @"Observed delivery results across the workspace.";
    _tabs.enabled = NO;
    _timeline.plan = nil;
    _timeline.acceptedBytes = nil;
    _documents = @[ overview ];
    [self changeTab:nil];
}
@end
