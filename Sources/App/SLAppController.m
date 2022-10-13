#import "SLAppController.h"
#import "SLTheme.h"
#import "SLInspector.h"
#import "SLReactor.h"
#import "SLBundle.h"
#import "SLHAR.h"
#import "SLReport.h"
#import "SLJSON.h"
#import "SLBytes.h"
#import "SLError.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation SLAppController {
    NSWindow *_window;
    NSTableView *_table;
    NSSearchField *_search;
    NSSegmentedControl *_scope;
    SLInspector *_inspector;
    NSTextField *_status;
    NSTextField *_workspaceLabel;
    NSTextField *_policyLabel;
    NSTextField *_scenarioLabel;
    NSTextField *_counts;
    NSTextField *_upstreamField;
    NSTextField *_portField;
    NSButton *_recordButton;
    NSButton *_replayButton;
    NSButton *_stopButton;
    NSArray<NSControl *> *_configurationControls;
    NSArray<SLFixture *> *_fixtures;
    NSArray<NSDictionary *> *_receipts;
    NSArray *_rows;
    NSString *_workspace;
    SLPrivacy *_privacy;
    SLScenario *_scenario;
    SLReactor *_reactor;
    dispatch_queue_t _dataQueue;
    dispatch_queue_t _networkQueue;
    NSTimer *_timer;
    BOOL _loading;
    BOOL _serving;
    BOOL _terminating;
    BOOL _smoke;
    BOOL _snapshotTaken;
    NSString *_snapshotPath;
    NSUInteger _generation;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _privacy=SLPrivacy.metadataOnly; _scenario=SLScenario.passthrough; _fixtures=@[]; _receipts=@[]; _rows=@[];
    _dataQueue=dispatch_queue_create("dev.sluice.workspace",DISPATCH_QUEUE_SERIAL);
    _networkQueue=dispatch_queue_create("dev.sluice.network",DISPATCH_QUEUE_SERIAL);
    NSArray *args=NSProcessInfo.processInfo.arguments;
    _workspace=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"Sluice"];
    for (NSUInteger i=1;i<args.count;i++) {
        if ([args[i] isEqual:@"--workspace"] && i+1<args.count) _workspace=args[++i];
        else if ([args[i] isEqual:@"--smoke"]) _smoke=YES;
        else if ([args[i] isEqual:@"--snapshot"] && i+1<args.count) _snapshotPath=args[++i];
    }
    [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
    [self menu]; [self buildWindow]; [_window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self refresh:nil];
    __weak SLAppController *weak=self;
    _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weak refresh:nil]; }];
}
- (void)menu {
    NSMenu *main=[NSMenu new]; NSMenuItem *root=[NSMenuItem new]; [main addItem:root];
    NSMenu *app=[NSMenu new]; root.submenu=app;
    [app addItemWithTitle:@"About Sluice" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Quit Sluice" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *editItem=[NSMenuItem new]; [main addItem:editItem]; editItem.submenu=[[NSMenu alloc] initWithTitle:@"Edit"];
    for (NSArray *entry in @[@[@"Copy",@"copy:",@"c"],@[@"Paste",@"paste:",@"v"],@[@"Select All",@"selectAll:",@"a"]]) [editItem.submenu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:entry[2]];
    NSApp.mainMenu=main;
}
- (void)buildWindow {
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    _window.title=@"Sluice"; _window.minSize=NSMakeSize(1080,720); _window.delegate=self;
    _window.backgroundColor=SLTheme.background; _window.titlebarAppearsTransparent=YES; [_window center];
    NSView *root=_window.contentView; root.wantsLayer=YES; root.layer.backgroundColor=SLTheme.background.CGColor;
    NSTextField *brand=[SLTheme label:@"sluice" size:32 weight:NSFontWeightBold];
    NSTextField *tagline=[SLTheme label:@"REHEARSE THE FAILURE" size:10 weight:NSFontWeightMedium]; tagline.textColor=SLTheme.accent;
    _workspaceLabel=[SLTheme label:_workspace.lastPathComponent size:11 weight:NSFontWeightRegular]; _workspaceLabel.textColor=SLTheme.muted;
    NSButton *workspace=[SLTheme button:@"Workspace" symbol:@"folder" target:self action:@selector(chooseWorkspace:)];
    NSButton *import=[SLTheme button:@"Import" symbol:@"square.and.arrow.down" target:self action:@selector(importFile:)];
    NSButton *export=[SLTheme button:@"Export" symbol:@"square.and.arrow.up" target:self action:@selector(exportFile:)];
    NSButton *policy=[SLTheme button:@"Privacy" symbol:@"lock.shield" target:self action:@selector(choosePrivacy:)];
    NSButton *scenario=[SLTheme button:@"Scenario" symbol:@"slider.horizontal.3" target:self action:@selector(chooseScenario:)];
    NSButton *refresh=[SLTheme button:@"Refresh" symbol:@"arrow.clockwise" target:self action:@selector(refresh:)];
    NSStackView *tools=[NSStackView stackViewWithViews:@[workspace,import,export,policy,scenario,refresh]]; tools.spacing=8;
    _upstreamField=[[NSTextField alloc] initWithFrame:NSZeroRect]; _upstreamField.stringValue=@"http://127.0.0.1:9000"; _upstreamField.font=[SLTheme mono:12]; _upstreamField.placeholderString=@"HTTP upstream"; _upstreamField.accessibilityLabel=@"Upstream HTTP origin";
    _portField=[[NSTextField alloc] initWithFrame:NSZeroRect]; _portField.stringValue=@"8080"; _portField.font=[SLTheme mono:12]; _portField.accessibilityLabel=@"Local listener port";
    _recordButton=[SLTheme button:@"Record" symbol:@"record.circle" target:self action:@selector(record:)];
    _replayButton=[SLTheme button:@"Replay" symbol:@"play.fill" target:self action:@selector(replay:)]; _replayButton.contentTintColor=SLTheme.accent;
    _stopButton=[SLTheme button:@"Stop" symbol:@"stop.fill" target:self action:@selector(stop:)]; _stopButton.enabled=NO;
    NSTextField *upstreamLabel=[SLTheme label:@"UPSTREAM" size:10 weight:NSFontWeightMedium]; upstreamLabel.textColor=SLTheme.muted;
    NSTextField *portLabel=[SLTheme label:@"LOCAL PORT" size:10 weight:NSFontWeightMedium]; portLabel.textColor=SLTheme.muted;
    NSStackView *transport=[NSStackView stackViewWithViews:@[upstreamLabel,_upstreamField,portLabel,_portField,_recordButton,_replayButton,_stopButton]]; transport.spacing=10;
    [_upstreamField.widthAnchor constraintEqualToConstant:290].active=YES; [_portField.widthAnchor constraintEqualToConstant:65].active=YES;
    _policyLabel=[SLTheme label:@"Privacy: metadata only" size:11 weight:NSFontWeightRegular]; _policyLabel.textColor=SLTheme.muted;
    _scenarioLabel=[SLTheme label:@"Scenario: passthrough" size:11 weight:NSFontWeightRegular]; _scenarioLabel.textColor=SLTheme.muted;
    _counts=[SLTheme label:@"0 fixtures  ·  0 deliveries" size:11 weight:NSFontWeightMedium];
    _scope=[NSSegmentedControl segmentedControlWithLabels:@[@"Fixtures",@"Deliveries",@"Overview"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(scopeChanged:)]; _scope.selectedSegment=0;
    _search=[NSSearchField new]; _search.placeholderString=@"Filter method, path, status, or identity"; _search.delegate=self; _search.sendsSearchStringImmediately=YES;
    _table=[[NSTableView alloc] initWithFrame:NSZeroRect]; _table.dataSource=self; _table.delegate=self; _table.rowHeight=48; _table.style=NSTableViewStyleFullWidth; _table.intercellSpacing=NSMakeSize(8,0); _table.backgroundColor=SLTheme.background; _table.usesAlternatingRowBackgroundColors=NO; _table.accessibilityLabel=@"Recorded fixtures and observed deliveries";
    for (NSArray *spec in @[@[@"kind",@"METHOD",@72],@[@"status",@"STATUS",@65],@[@"target",@"REQUEST / OUTCOME",@290]]) {
        NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:spec[0]]; column.title=spec[1]; column.width=[spec[2] doubleValue]; column.minWidth=45; [_table addTableColumn:column];
    }
    _table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    NSScrollView *list=[NSScrollView new]; list.documentView=_table; list.hasVerticalScroller=YES; list.borderType=NSNoBorder;
    _inspector=[[SLInspector alloc] initWithFrame:NSZeroRect];
    NSSplitView *split=[NSSplitView new]; split.vertical=YES; split.dividerStyle=NSSplitViewDividerStyleThin; [split addArrangedSubview:list]; [split addArrangedSubview:_inspector]; [split setHoldingPriority:240 forSubviewAtIndex:0]; [split setHoldingPriority:250 forSubviewAtIndex:1];
    [list.widthAnchor constraintGreaterThanOrEqualToConstant:400].active=YES; [_inspector.widthAnchor constraintGreaterThanOrEqualToConstant:430].active=YES;
    _status=[SLTheme label:@"Ready. Record an HTTP dependency or import a fixture." size:11 weight:NSFontWeightRegular]; _status.textColor=SLTheme.muted;
    NSView *line=[SLTheme separator]; NSView *bottomLine=[SLTheme separator];
    NSArray *views=@[brand,tagline,_workspaceLabel,tools,transport,_policyLabel,_scenarioLabel,_counts,_scope,_search,split,_status,line,bottomLine];
    for (NSView *v in views) { v.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [brand.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:26],[brand.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [tagline.leadingAnchor constraintEqualToAnchor:brand.trailingAnchor constant:18],[tagline.centerYAnchor constraintEqualToAnchor:brand.centerYAnchor constant:5],
        [tools.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-22],[tools.centerYAnchor constraintEqualToAnchor:brand.centerYAnchor],
        [_workspaceLabel.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:4],[_workspaceLabel.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[_workspaceLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [transport.topAnchor constraintEqualToAnchor:_workspaceLabel.bottomAnchor constant:22],[transport.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],
        [_policyLabel.topAnchor constraintEqualToAnchor:transport.bottomAnchor constant:14],[_policyLabel.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[_policyLabel.widthAnchor constraintEqualToConstant:300],
        [_scenarioLabel.leadingAnchor constraintEqualToAnchor:_policyLabel.trailingAnchor constant:20],[_scenarioLabel.centerYAnchor constraintEqualToAnchor:_policyLabel.centerYAnchor],[_scenarioLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-20],
        [line.topAnchor constraintEqualToAnchor:_policyLabel.bottomAnchor constant:16],[line.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[line.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scope.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:16],[_scope.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],
        [_counts.centerYAnchor constraintEqualToAnchor:_scope.centerYAnchor],[_counts.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [_search.topAnchor constraintEqualToAnchor:_scope.bottomAnchor constant:12],[_search.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[_search.widthAnchor constraintEqualToConstant:460],
        [split.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:12],[split.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],[split.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[split.bottomAnchor constraintEqualToAnchor:bottomLine.topAnchor constant:-8],
        [bottomLine.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[bottomLine.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[bottomLine.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-38],
        [_status.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[_status.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],[_status.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12]
    ]];
    _configurationControls=@[workspace,import,policy,scenario,_upstreamField,_portField,_recordButton,_replayButton];
    dispatch_async(dispatch_get_main_queue(),^{ [split setPosition:570 ofDividerAtIndex:0]; });
}
- (void)error:(SLError *)error {
    _status.stringValue=[NSString stringWithFormat:@"%@ · %@",error.code,error.reason ?: @"Operation failed"];
    if (_smoke) { fprintf(stderr,"%s\n",_status.stringValue.UTF8String); exit(2); }
    NSAlert *alert=[NSAlert new]; alert.messageText=error.code; alert.informativeText=error.reason ?: @"Operation failed"; [alert beginSheetModalForWindow:_window completionHandler:nil];
}
- (void)setServing:(BOOL)serving {
    _serving=serving; for (NSControl *control in _configurationControls) control.enabled=!serving;
    _stopButton.enabled=serving;
}
- (void)refresh:(id)sender {
    if (_loading) return; _loading=YES;
    NSString *path=[_workspace copy]; NSUInteger generation=_generation;
    dispatch_async(_dataQueue,^{ @autoreleasepool { @try {
        SLStore *store=[[SLStore alloc] initWithDirectory:path]; NSArray *fixtures=store.fixtures; NSArray *receipts=[store receipts:2000];
        dispatch_async(dispatch_get_main_queue(),^{
            self->_loading=NO; if (generation!=self->_generation) return;
            self->_fixtures=fixtures; self->_receipts=receipts;
            self->_counts.stringValue=[NSString stringWithFormat:@"%lu fixtures  ·  %lu recent deliveries",(unsigned long)fixtures.count,(unsigned long)receipts.count];
            self->_workspaceLabel.stringValue=path; [self filterRows];
            if (self->_smoke && !self->_snapshotTaken) {
                self->_snapshotTaken=YES;
                if (self->_rows.count) [self->_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self snapshotAndExit]; });
            }
        });
    } @catch (SLError *error) { dispatch_async(dispatch_get_main_queue(),^{ self->_loading=NO; [self error:error]; }); } }});
}
- (void)filterRows {
    id previous=_table.selectedRow>=0 && (NSUInteger)_table.selectedRow<_rows.count ? _rows[(NSUInteger)_table.selectedRow] : nil;
    NSString *selected=[previous isKindOfClass:SLFixture.class] ? [previous identifier] : previous[@"id"];
    NSArray *source=_scope.selectedSegment==0 ? (NSArray *)_fixtures : (NSArray *)_receipts;
    NSString *query=_search.stringValue.lowercaseString; NSMutableArray *rows=[NSMutableArray array];
    for (id item in source) {
        NSString *text;
        if ([item isKindOfClass:SLFixture.class]) { SLFixture *f=item; text=[NSString stringWithFormat:@"%@ %@ %@ %ld",f.identity,f.request.method,f.request.target,(long)f.response.status]; }
        else text=[NSString stringWithFormat:@"%@ %@ %@",item[@"identity"],item[@"outcome"],item[@"plan"][@"status"] ?: @""];
        if (!query.length || [text.lowercaseString containsString:query]) [rows addObject:item];
    }
    _rows=[rows copy]; [_table reloadData];
    NSUInteger index=NSNotFound;
    for (NSUInteger i=0;i<_rows.count;i++) { id item=_rows[i]; NSString *identifier=[item isKindOfClass:SLFixture.class] ? [item identifier] : item[@"id"]; if ([identifier isEqual:selected]) { index=i; break; } }
    if (index!=NSNotFound) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    if (_scope.selectedSegment==2) [_inspector showOverview:SLReceiptReport(_receipts)];
    else if (index==NSNotFound) [_inspector showEmpty];
}
- (void)scopeChanged:(id)sender { [_table deselectAll:nil]; [self filterRows]; }
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object==_search) [self filterRows]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _scope.selectedSegment==2 ? 0 : (NSInteger)_rows.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *field=[tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!field) { field=[SLTheme label:@"" size:11 weight:NSFontWeightRegular]; field.identifier=column.identifier; field.font=[SLTheme mono:11]; field.lineBreakMode=NSLineBreakByTruncatingMiddle; }
    id item=_rows[(NSUInteger)row]; NSString *text=@"";
    if ([item isKindOfClass:SLFixture.class]) {
        SLFixture *fixture=item;
        if ([column.identifier isEqual:@"kind"]) text=fixture.request.method;
        else if ([column.identifier isEqual:@"status"]) text=@(fixture.response.status).stringValue;
        else text=fixture.request.target;
    } else {
        if ([column.identifier isEqual:@"kind"]) text=item[@"mode"];
        else if ([column.identifier isEqual:@"status"]) text=[item[@"plan"][@"status"] description] ?: @"-";
        else text=[NSString stringWithFormat:@"%@  ·  %.1f ms",item[@"outcome"],[item[@"elapsedUs"] doubleValue]/1000];
    }
    field.stringValue=text; field.toolTip=text; field.textColor=[column.identifier isEqual:@"status"] && text.integerValue>=400 ? NSColor.systemOrangeColor : [column.identifier isEqual:@"kind"] ? SLTheme.accent : NSColor.labelColor;
    return field;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row=_table.selectedRow;
    if (row<0 || (NSUInteger)row>=_rows.count || _scope.selectedSegment==2) return;
    @try {
        id item=_rows[(NSUInteger)row];
        if ([item isKindOfClass:SLFixture.class]) { [_inspector showFixture:item scenario:_scenario]; if (!_serving) _replayButton.title=@"Replay fixture"; }
        else { [_inspector showReceipt:item]; if (!_serving) _replayButton.title=@"Replay"; }
    } @catch (SLError *error) { [self error:error]; }
}
- (void)chooseWorkspace:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO; panel.canCreateDirectories=YES; panel.prompt=@"Use workspace";
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) { if (response==NSModalResponseOK) { self->_workspace=panel.URL.path; self->_generation++; [self->_table deselectAll:nil]; [self refresh:nil]; } }];
}
- (void)chooseDocument:(void (^)(NSString *path))selected {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=NO; panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) { if (response==NSModalResponseOK) selected(panel.URL.path); }];
}
- (void)choosePrivacy:(id)sender {
    [self chooseDocument:^(NSString *path) { @try { self->_privacy=[[SLPrivacy alloc] initWithDocument:SLJSONRead(SLReadFile(path,1024*1024))]; self->_policyLabel.stringValue=[NSString stringWithFormat:@"Privacy: %@ bodies · %@",self->_privacy.bodyMode,[self->_privacy.digest substringToIndex:8]]; } @catch (SLError *error) { [self error:error]; } }];
}
- (void)chooseScenario:(id)sender {
    [self chooseDocument:^(NSString *path) { @try { self->_scenario=[[SLScenario alloc] initWithDocument:SLJSONRead(SLReadFile(path,1024*1024))]; self->_scenarioLabel.stringValue=[@"Scenario: " stringByAppendingString:self->_scenario.name]; [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self->_table]]; } @catch (SLError *error) { [self error:error]; } }];
}
- (void)importFile:(id)sender {
    [self chooseDocument:^(NSString *path) {
        NSString *workspace=[self->_workspace copy]; SLPrivacy *privacy=self->_privacy;
        dispatch_async(self->_dataQueue,^{ @autoreleasepool { @try {
            NSData *data=SLReadFile(path,32*1024*1024); NSDictionary *document=SLObject(SLJSONRead(data),@"import");
            NSArray *fixtures=document[@"log"] ? SLHARImport(data,privacy) : SLBundleDecode(data);
            SLStore *store=[[SLStore alloc] initWithDirectory:workspace]; [store importFixtures:fixtures];
            dispatch_async(dispatch_get_main_queue(),^{ self->_status.stringValue=[NSString stringWithFormat:@"Imported %lu validated fixtures.",(unsigned long)fixtures.count]; [self refresh:nil]; });
        } @catch (SLError *error) { dispatch_async(dispatch_get_main_queue(),^{ [self error:error]; }); } }});
    }];
}
- (void)exportFile:(id)sender {
    NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"fixtures.sluice.json";
    NSArray *fixtures=[_fixtures copy]; NSInteger selected=_table.selectedRow;
    if (_scope.selectedSegment==0 && selected>=0 && (NSUInteger)selected<_rows.count) fixtures=@[_rows[(NSUInteger)selected]];
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) { if (response!=NSModalResponseOK) return;
        NSString *path=panel.URL.path; dispatch_async(self->_dataQueue,^{ @autoreleasepool { @try {
            SLAtomicWrite(SLBundleEncode(fixtures),path);
            dispatch_async(dispatch_get_main_queue(),^{ self->_status.stringValue=[NSString stringWithFormat:@"Exported %lu privacy-filtered fixtures.",(unsigned long)fixtures.count]; });
        } @catch (SLError *error) { dispatch_async(dispatch_get_main_queue(),^{ [self error:error]; }); } }});
    }];
}
- (void)record:(id)sender { [self start:@"record" fixture:nil]; }
- (void)replay:(id)sender {
    NSString *fixture=nil; NSInteger selected=_table.selectedRow;
    if (_scope.selectedSegment==0 && selected>=0 && (NSUInteger)selected<_rows.count) fixture=[_rows[(NSUInteger)selected] identifier];
    [self start:@"replay" fixture:fixture];
}
- (void)start:(NSString *)mode fixture:(NSString *)fixture {
    if (_serving) return;
    @try {
        NSScanner *scanner=[NSScanner scannerWithString:_portField.stringValue]; scanner.charactersToBeSkipped=nil; int port=0;
        SLRequire([scanner scanInt:&port] && scanner.isAtEnd && port>=0 && port<=65535,@"ui.port",@"Local port must be 0 through 65535");
        SLEndpoint *upstream=[mode isEqual:@"record"] ? [SLEndpoint parse:_upstreamField.stringValue] : nil;
        NSString *workspace=[_workspace copy]; SLPrivacy *privacy=_privacy; SLScenario *scenario=_scenario;
        [self setServing:YES]; _status.stringValue=@"Starting local listener...";
        dispatch_async(_networkQueue,^{ @autoreleasepool { @try {
            SLStore *store=[[SLStore alloc] initWithDirectory:workspace];
            SLSession *session=[[SLSession alloc] initMode:mode store:store privacy:privacy scenario:scenario fixture:fixture];
            SLReactor *reactor=[[SLReactor alloc] initSession:session upstream:upstream port:(uint16_t)port];
            dispatch_async(dispatch_get_main_queue(),^{ self->_reactor=reactor; if (self->_terminating) [reactor stop]; });
            [reactor runReady:^(uint16_t actual) { dispatch_async(dispatch_get_main_queue(),^{ self->_status.stringValue=[NSString stringWithFormat:@"%@ on http://127.0.0.1:%u · %@",[mode isEqual:@"record"]?@"Recording":@"Replaying",actual,scenario.name]; }); }];
            if (reactor.fatalError) SLFail(@"reactor.storage",reactor.fatalError);
            dispatch_async(dispatch_get_main_queue(),^{ self->_reactor=nil; [self setServing:NO]; self->_status.stringValue=@"Listener stopped. Delivery receipts saved."; [self refresh:nil]; if (self->_terminating) [NSApp replyToApplicationShouldTerminate:YES]; });
        } @catch (SLError *error) { dispatch_async(dispatch_get_main_queue(),^{ self->_reactor=nil; [self setServing:NO]; if (self->_terminating) [NSApp replyToApplicationShouldTerminate:YES]; else [self error:error]; }); } }});
    } @catch (SLError *error) { [self error:error]; }
}
- (void)stop:(id)sender { [_reactor stop]; _status.stringValue=@"Stopping listener..."; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [_timer invalidate]; _timer=nil;
    if (_serving) { _terminating=YES; [_reactor stop]; return NSTerminateLater; }
    return NSTerminateNow;
}
- (BOOL)windowShouldClose:(NSWindow *)sender { [NSApp terminate:nil]; return NO; }
- (void)snapshotAndExit {
    if (_snapshotPath) {
        [_window.contentView layoutSubtreeIfNeeded]; [_window displayIfNeeded];
        NSBitmapImageRep *bitmap=[_window.contentView bitmapImageRepForCachingDisplayInRect:_window.contentView.bounds];
        [_window.contentView cacheDisplayInRect:_window.contentView.bounds toBitmapImageRep:bitmap];
        NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        @try { SLRequire(png.length>0,@"ui.snapshot",@"Cannot render app snapshot"); SLAtomicWrite(png,_snapshotPath); }
        @catch (SLError *error) { [self error:error]; return; }
    }
    printf("{\"appSmoke\":true,\"fixtures\":%lu,\"receipts\":%lu}\n",(unsigned long)_fixtures.count,(unsigned long)_receipts.count); fflush(stdout); [NSApp terminate:nil];
}
@end
