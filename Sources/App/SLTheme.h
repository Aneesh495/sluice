#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface SLTheme : NSObject
+ (NSColor *)background;
+ (NSColor *)panel;
+ (NSColor *)accent;
+ (NSColor *)muted;
+ (NSFont *)mono:(CGFloat)size;
+ (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSButton *)button:(NSString *)title
              symbol:(NSString *)symbol
              target:(id)target
              action:(SEL)action;
+ (NSView *)separator;
@end
NS_ASSUME_NONNULL_END
