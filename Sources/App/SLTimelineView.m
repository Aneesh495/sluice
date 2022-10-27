#import "SLTimelineView.h"
#import "SLTheme.h"
@implementation SLTimelineView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = SLTheme.panel.CGColor;
        self.layer.cornerRadius = 10;
        self.accessibilityElement = YES;
        self.accessibilityLabel = @"Planned response delivery timeline";
    }
    return self;
}
- (BOOL)isFlipped {
    return YES;
}
- (void)setPlan:(NSDictionary *)plan {
    _plan = plan;
    self.needsDisplay = YES;
}
- (void)setAcceptedBytes:(NSNumber *)acceptedBytes {
    _acceptedBytes = acceptedBytes;
    self.needsDisplay = YES;
}
- (void)text:(NSString *)text at:(NSPoint)point color:(NSColor *)color size:(CGFloat)size {
    [text drawAtPoint:point
        withAttributes:@{
            NSFontAttributeName : [SLTheme mono:size],
            NSForegroundColorAttributeName : color
        }];
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self text:@"PLANNED DELIVERY" at:NSMakePoint(16, 14) color:SLTheme.muted size:10];
    if (!self.plan) {
        [self text:@"Select a fixture or delivery to inspect its timeline."
                at:NSMakePoint(16, 58)
             color:SLTheme.muted
              size:11];
        return;
    }
    double delay = [self.plan[@"delayUs"] doubleValue] / 1000.0;
    double duration = [self.plan[@"durationUs"] doubleValue] / 1000.0;
    double maximum = MAX(100.0, duration * 1.15);
    CGFloat left = 18, width = MAX(1, self.bounds.size.width - 36);
    for (int i = 0; i <= 4; i++) {
        CGFloat x = left + width * i / 4;
        [[NSColor colorWithWhite:1 alpha:0.07] setStroke];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(x, 42)];
        [line lineToPoint:NSMakePoint(x, 101)];
        [line stroke];
        [self text:[NSString stringWithFormat:@"%.0f ms", maximum * i / 4]
                at:NSMakePoint(x, 106)
             color:SLTheme.muted
              size:9];
    }
    CGFloat x = left + width * delay / maximum;
    NSRect wait = NSMakeRect(left, 54, MAX(2, x - left), 12);
    [[NSColor colorWithWhite:1 alpha:0.1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:wait xRadius:3 yRadius:3] fill];
    CGFloat span = MAX(4, width * (duration - delay) / maximum);
    [SLTheme.accent setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, 54, span, 12) xRadius:3 yRadius:3] fill];
    [self
         text:[NSString stringWithFormat:@"delay %.0f ms   last chunk due %.0f ms", delay, duration]
           at:NSMakePoint(18, 80)
        color:NSColor.labelColor
         size:10];
    NSString *detail = [NSString stringWithFormat:@"%@ bytes planned  ·  %@ segments  ·  %@",
                                                  self.plan[@"wireBytes"], self.plan[@"segments"],
                                                  [self.plan[@"rule"] description]];
    [self text:detail at:NSMakePoint(18, 135) color:SLTheme.muted size:10];
    if (self.acceptedBytes)
        [self text:[NSString stringWithFormat:@"%@ bytes accepted by socket", self.acceptedBytes]
                at:NSMakePoint(18, 154)
             color:SLTheme.accent
              size:10];
    self.accessibilityValue = [NSString
        stringWithFormat:
            @"Delay %.0f milliseconds, final chunk due %.0f milliseconds, %@ bytes planned", delay,
            duration, self.plan[@"wireBytes"]];
}
@end
