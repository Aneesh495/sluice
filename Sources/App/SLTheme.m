#import "SLTheme.h"
@implementation SLTheme
+ (NSColor *)background { return [NSColor colorWithCalibratedRed:0.055 green:0.065 blue:0.085 alpha:1]; }
+ (NSColor *)panel { return [NSColor colorWithCalibratedRed:0.085 green:0.10 blue:0.125 alpha:1]; }
+ (NSColor *)accent { return [NSColor colorWithCalibratedRed:0.29 green:0.84 blue:0.72 alpha:1]; }
+ (NSColor *)muted { return [NSColor colorWithCalibratedRed:0.56 green:0.62 blue:0.69 alpha:1]; }
+ (NSFont *)mono:(CGFloat)size { return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]; }
+ (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *field=[NSTextField labelWithString:text]; field.font=[NSFont systemFontOfSize:size weight:weight]; field.textColor=NSColor.labelColor; field.lineBreakMode=NSLineBreakByTruncatingTail; return field;
}
+ (NSButton *)button:(NSString *)title symbol:(NSString *)symbol target:(id)target action:(SEL)action {
    NSButton *button=[NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle=NSBezelStyleRounded; button.controlSize=NSControlSizeRegular;
    button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title]; button.imagePosition=NSImageLeading; button.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.toolTip=title; return button;
}
+ (NSView *)separator {
    NSBox *box=[NSBox new]; box.boxType=NSBoxSeparator; return box;
}
@end
