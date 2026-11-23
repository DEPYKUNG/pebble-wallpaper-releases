#import "PebbleAppInternal.h"

static NSString *const PetEnabledKey=@"DesktopPetEnabled";

@implementation PebbleApp (Pet)
- (void)configurePetMenu:(NSMenu *)menu {
    NSMenuItem *entry=[menu addItemWithTitle:@"桌宠" action:nil keyEquivalent:@""];
    NSMenu *petMenu=[NSMenu new];entry.submenu=petMenu;
    self.petEnabledItem=[self addItem:@"开启桌宠" action:@selector(togglePet:) toMenu:petMenu];
    self.petRoamingItem=[self addItem:@"自由活动" action:@selector(togglePetRoaming:) toMenu:petMenu];
    NSMenuItem *size=[petMenu addItemWithTitle:@"桌宠大小" action:nil keyEquivalent:@""];size.submenu=[NSMenu new];
    NSArray *titles=@[@"小",@"中",@"大"];
    for (NSInteger i=0;i<3;i++){NSMenuItem *item=[self addItem:titles[i] action:@selector(selectPetSize:) toMenu:size.submenu];item.tag=i;}
    [self addItem:@"同步当前石头" action:@selector(syncPetStone) toMenu:petMenu];
    [self addItem:@"收回右下角" action:@selector(summonPet:) toMenu:petMenu];
    [self addItem:@"桌宠设置…" action:@selector(showPetSettings:) toMenu:petMenu];
    [self syncPetControls];
}
- (void)showPetSettings:(id)sender {
    [self showSettings:sender];[self showPaneAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.settings.contentView layoutSubtreeIfNeeded];
        NSScrollView *scroll=(NSScrollView *)self.panes[0];
        if([scroll isKindOfClass:NSScrollView.class]) {
            NSView *document=scroll.documentView;
            [document scrollPoint:NSMakePoint(0,MAX(0,NSHeight(document.bounds)-NSHeight(scroll.contentView.bounds)))];
        }
    });
}
- (void)updatePetPresentation {
    if (self.testPreviewPath || self.shotPath || self.settingsPreview) return;
    BOOL enabled=self.petPreview ? !self.petPreviewDismissed : [NSUserDefaults.standardUserDefaults boolForKey:PetEnabledKey];
    if (!enabled) {
        self.petGeneration++;[self.pet invalidate];self.pet=nil;
        [self forEachRenderer:^(WKWebView *web){[web evaluateJavaScript:@"window.pebbleReleasePet?.()" completionHandler:nil];}];[self syncPetControls];return;
    }
    if (!self.pet) {
        self.pet=[[PebblePetController alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        __weak PebbleApp *weakSelf=self;
        self.pet.syncStone=^{[weakSelf syncPetStone];};
        self.pet.dismissPet=^{[weakSelf togglePet:nil];};
        self.pet.openSettings=^{[weakSelf showPetSettings:nil];};
        self.pet.interactionEnded=^{
            [weakSelf syncPetControls];
#if __has_include(<Sparkle/Sparkle.h>)
            [weakSelf installPendingUpdateIfIdle];
#endif
        };
        [self syncPetStone];
    }
    // Privacy/power boundaries apply even when wallpaper smart pause is disabled.
    [self.pet setSuspended:self.screenLocked || self.displaysAsleep || self.sessionInactive || !NSScreen.screens.count];
    [self syncPetControls];
}
- (void)syncPetStone {
    if (!self.pet || self.petSyncScheduled) return;
    self.petSyncScheduled=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,160*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        self.petSyncScheduled=NO;
        PebblePetController *pet=self.pet;if(!pet)return;
        NSNumber *display=(pet.panel.screen ?: NSScreen.mainScreen).deviceDescription[@"NSScreenNumber"];
        WKWebView *web=(WKWebView *)self.desktopWindows[display].contentView;
        if (!web) web=(WKWebView *)self.desktopWindows.allValues.firstObject.contentView;
        if (!web || web.loading) return; // didFinishNavigation will request a fresh sprite.
        NSUInteger generation=++self.petGeneration;
        [self performWallpaperScript:@"window.pebblePetFrame?.()" inWeb:web reportErrors:NO completion:^(id encoded,NSError *error){
            if (generation!=self.petGeneration || self.pet!=pet || error) return;
            NSData *data=[encoded isKindOfClass:NSString.class]?[[NSData alloc] initWithBase64EncodedString:encoded options:0]:nil;
            if (![pet setStonePNG:data]) NSLog(@"Desktop pet sprite unavailable; keeping the last valid image.");
            if (self.petPreview) {
                for(NSWindow *window in self.desktopWindows.allValues)[window orderOut:nil];
                for(NSPanel *panel in self.desktopControls.allValues)[panel orderOut:nil];
            }
        }];
    });
}
- (void)togglePet:(id)sender {
    BOOL enabled=self.pet!=nil || (!self.petPreview && [NSUserDefaults.standardUserDefaults boolForKey:PetEnabledKey]);
    if (self.petPreview) self.petPreviewDismissed=enabled;
    else [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:PetEnabledKey];
    [self updatePetPresentation];
}
- (void)togglePetRoaming:(id)sender {
    BOOL enabled=self.pet ? !self.pet.roaming : [NSUserDefaults.standardUserDefaults boolForKey:@"DesktopPetQuiet"];
    [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:@"DesktopPetQuiet"];
    self.pet.roaming=enabled;[self syncPetControls];
}
- (void)selectPetSize:(id)sender {
    NSInteger size=[sender isKindOfClass:NSPopUpButton.class]?[(NSPopUpButton *)sender indexOfSelectedItem]:[sender tag];
    size=MAX(0,MIN(2,size));[NSUserDefaults.standardUserDefaults setInteger:size forKey:@"DesktopPetSize"];
    self.pet.sizeIndex=size;[self syncPetControls];
}
- (void)summonPet:(id)sender {
    if (!self.pet) {
        if(self.petPreview)self.petPreviewDismissed=NO;
        else [NSUserDefaults.standardUserDefaults setBool:YES forKey:PetEnabledKey];
        [self updatePetPresentation];
    }
    [self.pet summon:sender];[self syncPetStone];
}
- (void)syncPetControls {
    BOOL enabled=self.pet!=nil || (!self.petPreview && !self.settingsPreview && !self.shotPath && !self.testPreviewPath && [NSUserDefaults.standardUserDefaults boolForKey:PetEnabledKey]);
    BOOL roaming=self.pet ? self.pet.roaming : ![NSUserDefaults.standardUserDefaults boolForKey:@"DesktopPetQuiet"];
    NSInteger size=self.pet?self.pet.sizeIndex:([NSUserDefaults.standardUserDefaults objectForKey:@"DesktopPetSize"]?MAX(0,MIN(2,[NSUserDefaults.standardUserDefaults integerForKey:@"DesktopPetSize"])):1);
    self.petEnabledItem.state=enabled;self.petRoamingItem.state=roaming;
    self.petSwitch.state=enabled;self.petRoamSwitch.state=roaming;self.petRoamSwitch.enabled=enabled;
    [self.petSizePicker selectItemAtIndex:size];
    NSMenu *menu=self.petEnabledItem.menu;
    for(NSMenuItem *item in menu.itemArray) if(item.submenu) for(NSMenuItem *choice in item.submenu.itemArray) choice.state=choice.tag==size;
}
- (NSView *)petSettingsGroup {
    self.petSwitch=[self switchOn:NO action:@selector(togglePet:)];
    self.petRoamSwitch=[self switchOn:YES action:@selector(togglePetRoaming:)];
    self.petSizePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.petSizePicker addItemsWithTitles:@[@"小",@"中",@"大"]];self.petSizePicker.target=self;self.petSizePicker.action=@selector(selectPetSize:);
    NSStackView *actions=[NSStackView stackViewWithViews:@[[self actionButton:@"同步石头" action:@selector(syncPetStone)],
        [self actionButton:@"收回右下角" action:@selector(summonPet:)]]];actions.spacing=8;
    NSView *card=[self cardWithRows:@[
        [self rowWithSymbol:@"smile" title:@"开启桌宠" subtitle:@"把当前石头带到窗口旁，点一下打招呼" control:self.petSwitch],
        [self rowWithSymbol:@"rotate-cw" title:@"自由活动" subtitle:@"轻轻跳动；关闭后安静陪伴，仍可拖动" control:self.petRoamSwitch],
        [self rowWithSymbol:@"grid" title:@"桌宠大小" subtitle:nil control:self.petSizePicker],
        [self rowWithSymbol:@"repeat" title:@"拖动与轻抛" subtitle:@"拖住移动，松手轻抛；右键查看更多操作" control:actions],
    ]];[self syncPetControls];return [self settingsGroup:@"石头桌宠" containing:card];
}

#if __has_include(<Sparkle/Sparkle.h>)
- (void)verifyPetUpdateDeferral {
    NSString *suite=[@"app.painted-pebble.petupdateverification." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    PebblePetController *pet=[[PebblePetController alloc] initWithDefaults:defaults];self.pet=pet;
    [pet setValue:@YES forKey:@"dragging"];
    __block NSUInteger installs=0;
    [self stageUpdateInstallation:^{installs++;}];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(installs || !self.pendingInstall)exit(19);
        [pet setValue:@NO forKey:@"dragging"];[pet setValue:@YES forKey:@"menuOpen"];
        [self installPendingUpdateIfIdle];if(installs)exit(19);
        [pet setValue:@NO forKey:@"menuOpen"];[self installPendingUpdateIfIdle];
        if(installs!=1)exit(19);
        [self resetPendingUpdate];[pet invalidate];self.pet=nil;
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Update installation defers during pet dragging/menu tracking and resumes after interaction.");
        [NSApp terminate:nil];
    });
}
#endif

- (void)verifyPetRenderer:(WKWebView *)web then:(void (^)(void))next {
    NSString *script=@"(()=>{const before=JSON.stringify(window.pebbleSnapshot());"
        "const current=window.pebbleHistory?.current,oldRecord=current?.faces,oldConfig=window.pebbleConfig.faces;"
        "const faces=value=>{window.pebbleConfig.faces=value;if(current)current.faces=value;};let png,off;"
        "try{faces('on');png=window.pebblePetFrame();faces('off');off=window.pebblePetFrame();"
        "for(let i=0;i<12;i++)window.pebblePetFrame();}"
        "finally{window.pebbleConfig.faces=oldConfig;if(current)current.faces=oldRecord;}"
        "return {png,faceVisible:png!==off,alive:!document.querySelector('canvas').getContext('webgl').isContextLost(),"
        "unchanged:before===JSON.stringify(window.pebbleSnapshot())}})()";
    [web evaluateJavaScript:script completionHandler:^(NSDictionary *result,NSError *error){
        NSData *png=[result[@"png"] isKindOfClass:NSString.class]?[[NSData alloc] initWithBase64EncodedString:result[@"png"] options:0]:nil;
        NSBitmapImageRep *bitmap=png?[NSBitmapImageRep imageRepWithData:png]:nil;
        if(error || ![result[@"faceVisible"] boolValue] || ![result[@"alive"] boolValue] || ![result[@"unchanged"] boolValue] || bitmap.pixelsWide!=640 || bitmap.pixelsHigh!=640 ||
           !bitmap.hasAlpha || [bitmap colorAtX:0 y:0].alphaComponent>.01 || [bitmap colorAtX:320 y:320].alphaComponent<.1){
            NSLog(@"Pet export failed: error=%@ alive=%@ unchanged=%@ size=%ldx%ld alpha=%d",error,result[@"alive"],result[@"unchanged"],(long)bitmap.pixelsWide,(long)bitmap.pixelsHigh,bitmap.hasAlpha);exit(18);
        }
        NSString *sprite=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-frame-verification.png"];
        if(![png writeToFile:sprite atomically:YES])exit(18);
        NSString *suite=[@"app.painted-pebble.petverification." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        PebblePetController *pet=[[PebblePetController alloc] initWithDefaults:defaults];
        [pet setSuspended:YES];
        if(![pet setStonePNG:png] || pet.panel.opaque || pet.panel.canBecomeKeyWindow || pet.panel.isVisible)exit(18);
        BOOL hit=NO,miss=NO;
        NSRect frame=pet.panel.frame;
        for(NSUInteger x=0;x<12;x++)for(NSUInteger y=0;y<12;y++){
            BOOL solid=[pet containsStoneAtScreenPoint:NSMakePoint(NSMinX(frame)+x*NSWidth(frame)/12,NSMinY(frame)+y*NSHeight(frame)/12)];
            hit|=solid;miss|=!solid;
        }
        if(!hit || !miss || [pet containsStoneAtScreenPoint:frame.origin])exit(18);
        NSPoint pointer=NSMakePoint(NSMidX(frame),NSMidY(frame));
        [pet beginDragAtPoint:pointer time:1];
        if(!pet.dragging || !pet.interacting)exit(18);
        [pet dragToPoint:NSMakePoint(pointer.x-90,pointer.y+80) time:1.05];
        if(NSEqualPoints(frame.origin,pet.panel.frame.origin))exit(18);
        [pet endDragAtTime:1.08];if(pet.dragging || pet.interacting)exit(18);
        [pet beginDragAtPoint:pointer time:2];[pet setSuspended:YES];
        if(pet.dragging || pet.panel.isVisible)exit(18);
        pet.sizeIndex=2;pet.roaming=NO;
        NSView *view=pet.panel.contentView;
        NSBitmapImageRep *drawing=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:drawing];
        NSString *windowImage=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-window-verification.png"];
        if(![[drawing representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:windowImage atomically:YES])exit(18);
        if(pet.sizeIndex!=2 || pet.roaming || !pet.stoneImage)exit(18);
        [pet invalidate];
        if(pet.panel.isVisible || [pet valueForKey:@"timer"])exit(18);
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Transparent pet sprite, burst exports preserving the live context/stone, pointer samples, nonactivating window, size/quiet settings and teardown verified.");next();
    }];
}
@end
