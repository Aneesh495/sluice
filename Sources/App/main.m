#import <AppKit/AppKit.h>
#import "SLAppController.h"
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSApplication *application=NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        SLAppController *controller=[SLAppController new]; application.delegate=controller;
        [application run]; return 0;
    }
}
