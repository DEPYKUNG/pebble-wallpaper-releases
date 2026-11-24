#import "PebbleAppInternal.h"

static NSString *const PetEnabledKey=@"DesktopPetEnabled";

@implementation PebbleApp (Pet)
- (void)configurePetMenu:(NSMenu *)menu {
    NSMenuItem *entry=[menu addItemWithTitle:@"桌宠控制" action:nil keyEquivalent:@""];
    NSMenu *petMenu=[NSMenu new];entry.submenu=petMenu;
    self.petEnabledItem=[self addItem:@"开启桌宠" action:@selector(togglePet:) toMenu:petMenu];
    self.petRoamingItem=[self addItem:@"自由活动" action:@selector(togglePetRoaming:) toMenu:petMenu];
    NSMenuItem *size=[petMenu addItemWithTitle:@"桌宠大小" action:nil keyEquivalent:@""];size.submenu=[NSMenu new];
    NSArray *titles=@[@"小",@"中",@"大"];
    for (NSInteger i=0;i<3;i++){NSMenuItem *item=[self addItem:titles[i] action:@selector(selectPetSize:) toMenu:size.submenu];item.tag=i;}
    [self addItem:@"同步当前石头" action:@selector(syncPetStone) toMenu:petMenu];
    [self addItem:@"收回右下角" action:@selector(summonPet:) toMenu:petMenu];
    [self addItem:@"打个水漂" action:@selector(skipPet:) toMenu:petMenu];
    [self addItem:@"说句话" action:@selector(sayPet:) toMenu:petMenu];
    [self addItem:@"桌宠设置…" action:@selector(showPetSettings:) toMenu:petMenu];
    [self syncPetControls];
}
- (void)showPetSettings:(id)sender {
    [self showSettings:sender];[self showPaneAtIndex:PetPaneIndex];
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
            [self syncPetControls];
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
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    BOOL skipping=self.pet?self.pet.skippingEnabled:![defaults boolForKey:@"DesktopPetSkippingDisabled"];
    BOOL speech=self.pet?self.pet.speechEnabled:![defaults boolForKey:@"DesktopPetSpeechDisabled"];
    BOOL chat=self.pet?self.pet.casualSpeech:[defaults boolForKey:@"DesktopPetCasualSpeech"];
    NSInteger limit=self.pet?self.pet.skipLimit:[defaults integerForKey:@"DesktopPetSkipLimit"];
    if(limit!=3 && limit!=7)limit=5;
    self.petSkippingSwitch.state=skipping;self.petSkippingSwitch.enabled=enabled;
    self.petSpeechSwitch.state=speech;self.petSpeechSwitch.enabled=enabled;
    self.petChatSwitch.state=chat;self.petChatSwitch.enabled=enabled&&speech;
    [self.petSkipLimitPicker selectItemWithTitle:[NSString stringWithFormat:@"%ld 次",(long)limit]];
    self.petSkipLimitPicker.enabled=enabled&&skipping;
    self.petSkipButton.enabled=enabled&&skipping&&self.pet.stoneImage!=nil;
    self.petSayButton.enabled=enabled&&speech&&self.pet.stoneImage!=nil;
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
        [self rowWithSymbol:@"rotate-cw" title:@"自由活动" subtitle:@"随机轻跳或表演小剧场；关闭后仍可手动互动" control:self.petRoamSwitch],
        [self rowWithSymbol:@"grid" title:@"桌宠大小" subtitle:nil control:self.petSizePicker],
        [self rowWithSymbol:@"repeat" title:@"带回身边" subtitle:@"同步所在屏幕的石头，或收回右下角" control:actions],
    ]];[self syncPetControls];return [self settingsGroup:@"石头桌宠" containing:card];
}


- (void)skipPet:(id)sender {[self.pet skip:sender];}
- (void)sayPet:(id)sender {[self.pet say:sender];}
- (void)togglePetOption:(id)sender {
    NSInteger option=[sender tag];if(option<0 || option>2)return;
    BOOL value=[sender state]==NSControlStateValueOn;
    NSArray *keys=@[@"DesktopPetSkippingDisabled",@"DesktopPetSpeechDisabled",@"DesktopPetCasualSpeech"];
    [NSUserDefaults.standardUserDefaults setBool:option<2?!value:value forKey:keys[option]];
    if(option==0)self.pet.skippingEnabled=value;
    if(option==1)self.pet.speechEnabled=value;
    if(option==2)self.pet.casualSpeech=value;
    [self syncPetControls];
}
- (void)selectPetSkipLimit:(NSPopUpButton *)sender {
    NSInteger count=sender.titleOfSelectedItem.integerValue;if(count!=3 && count!=7)count=5;
    [NSUserDefaults.standardUserDefaults setInteger:count forKey:@"DesktopPetSkipLimit"];
    self.pet.skipLimit=count;[self syncPetControls];
}
- (NSView *)petPane {
    NSView *companion=[self petSettingsGroup];
    self.petSkippingSwitch=[self switchOn:YES action:@selector(togglePetOption:)];self.petSkippingSwitch.tag=0;
    self.petSpeechSwitch=[self switchOn:YES action:@selector(togglePetOption:)];self.petSpeechSwitch.tag=1;
    self.petChatSwitch=[self switchOn:NO action:@selector(togglePetOption:)];self.petChatSwitch.tag=2;
    self.petSkipLimitPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.petSkipLimitPicker addItemsWithTitles:@[@"3 次",@"5 次",@"7 次"]];
    self.petSkipLimitPicker.target=self;self.petSkipLimitPicker.action=@selector(selectPetSkipLimit:);
    self.petSkipButton=[self actionButton:@"漂一下" action:@selector(skipPet:)];
    self.petSayButton=[self actionButton:@"说句话" action:@selector(sayPet:)];
    NSView *skipping=[self cardWithRows:@[
        [self rowWithSymbol:@"repeat" title:@"横甩打水漂" subtitle:@"快速横向甩出，在屏幕下方连跳并滑停" control:self.petSkippingSwitch],
        [self rowWithSymbol:@"gauge" title:@"最多弹跳" subtitle:@"遇到屏幕边缘会提前落定" control:self.petSkipLimitPicker],
        [self rowWithSymbol:@"compass-drawing" title:@"试试打水漂" subtitle:@"减少动态效果开启时暂停大幅运动" control:self.petSkipButton],
    ]];
    NSView *speech=[self cardWithRows:@[
        [self rowWithSymbol:@"smile" title:@"说话气泡" subtitle:@"点击时回应，水漂后报个数" control:self.petSpeechSwitch],
        [self rowWithSymbol:@"heart" title:@"偶尔说两句" subtitle:@"安静待着时，偶尔冒一句话" control:self.petChatSwitch],
        [self rowWithSymbol:@"info" title:@"试试气泡" subtitle:@"不用打开窗口，也能看见石头回应" control:self.petSayButton],
    ]];
    [self syncPetControls];
    return [self paneWithCards:@[companion,[self settingsGroup:@"屏幕打水漂" containing:skipping],[self settingsGroup:@"说话气泡" containing:speech]]];
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
        [pet setValue:@NO forKey:@"menuOpen"];[pet setValue:@YES forKey:@"skipEnding"];
        [self installPendingUpdateIfIdle];if(installs)exit(19);
        [pet setValue:@NO forKey:@"skipEnding"];[self installPendingUpdateIfIdle];
        if(installs!=1)exit(19);
        [self resetPendingUpdate];[pet invalidate];self.pet=nil;
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Update installation defers during pet dragging/menu tracking/skipping and resumes after interaction.");
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
        [pet setSuspended:NO];
        [pet beginDragAtPoint:pet.panel.frame.origin time:3];
        [pet dragToPoint:NSMakePoint(pet.panel.frame.origin.x-70,pet.panel.frame.origin.y) time:3.1];
        [pet endDragAtTime:3.11];
        if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && (!pet.skipping || !pet.interacting))exit(20);
        [pet setSuspended:YES];if(pet.skipping || pet.interacting)exit(20);
        if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && NSScreen.screens.count){
            pet.roaming=NO;[pet setSuspended:NO];[pet summon:nil];[pet skip:nil];
            double deadline=[NSDate timeIntervalSinceReferenceDate]+9;
            NSPoint initial=pet.panel.frame.origin;NSUInteger peakRipples=0;
            while(pet.interacting && [NSDate timeIntervalSinceReferenceDate]<deadline){
                [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.025]];
                peakRipples=MAX(peakRipples,pet.effects.rippleCount);
            }
            if(pet.interacting || !peakRipples || fabs(initial.x-pet.panel.frame.origin.x)<30 ||
               ![pet.effects.message hasPrefix:@"漂了 "]) {NSLog(@"Live skipping failed: %@ ripples=%lu",pet.effects.message,(unsigned long)peakRipples);exit(20);}
            NSView *liveBubble=pet.effects.bubblePanel.contentView;
            NSBitmapImageRep *livePNG=[liveBubble bitmapImageRepForCachingDisplayInRect:liveBubble.bounds];
            [liveBubble cacheDisplayInRect:liveBubble.bounds toBitmapImageRep:livePNG];
            NSString *livePath=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-skipping-bubble.png"];
            if(![[livePNG representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:livePath atomically:YES])exit(20);
            NSLog(@"Live timer skipping, visible ripples, settling and completion speech verified: %@",pet.effects.message);
            [pet setSuspended:YES];if(pet.effects.message || pet.effects.rippleCount)exit(20);
        }
        [pet setSuspended:NO];
        NSMenu *menu=[pet valueForKey:@"petMenu"];
        NSMenu *activities=[menu itemWithTitle:@"做点什么"].submenu;
        NSMenuItem *podcast=[activities itemWithTitle:@"录播客"];
        NSMenuItem *sleep=[activities itemWithTitle:@"睡觉"];
        if(!podcast || !sleep || ![NSApp sendAction:podcast.action to:podcast.target from:podcast] ||
           ![pet.panel.contentView.accessibilityValue isEqual:@"录播客中"] || !pet.effects.message.length)exit(21);
        NSView *podcastView=pet.panel.contentView;
        NSBitmapImageRep *podcastPreview=[podcastView bitmapImageRepForCachingDisplayInRect:podcastView.bounds];
        [podcastView cacheDisplayInRect:podcastView.bounds toBitmapImageRep:podcastPreview];
        NSString *podcastPath=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-podcast-preview.png"];
        if(![[podcastPreview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:podcastPath atomically:YES])exit(21);
        if(![NSApp sendAction:sleep.action to:sleep.target from:sleep] ||
           ![pet.panel.contentView.accessibilityValue isEqual:@"睡觉中"] || pet.effects.message)exit(21);
        NSBitmapImageRep *sleepPreview=[podcastView bitmapImageRepForCachingDisplayInRect:podcastView.bounds];
        [podcastView cacheDisplayInRect:podcastView.bounds toBitmapImageRep:sleepPreview];
        NSString *sleepPath=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-sleep-preview.png"];
        if(![[sleepPreview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:sleepPath atomically:YES])exit(21);
        NSPoint wakePoint=pet.panel.frame.origin;
        [pet beginDragAtPoint:wakePoint time:5];
        [pet endDragAtTime:5.01];
        if(pet.panel.contentView.accessibilityValue || pet.effects.message || pet.dragging)exit(21);
        NSArray *outingTitles=@[@"露营",@"野炊",@"戴耳机",@"砸玻璃"];
        NSArray *outingValues=@[@"露营中",@"野炊中",@"戴着耳机",@"砸玻璃中"];
        NSArray *outingFiles=@[@"pet-camp-preview.png",@"pet-cook-preview.png",@"pet-headphones-preview.png",@"pet-smash-preview.png"];
        for(NSUInteger i=0;i<outingTitles.count;i++){
            NSMenuItem *item=[activities itemWithTitle:outingTitles[i]];
            if(!item || ![NSApp sendAction:item.action to:item.target from:item] ||
               ![pet.panel.contentView.accessibilityValue isEqual:outingValues[i]])exit(21);
            if ([outingTitles[i] isEqual:@"砸玻璃"]) {
                NSPanel *glass=[pet valueForKey:@"glassPanel"];
                NSScreen *screen=pet.panel.screen ?: NSScreen.screens.firstObject;
                if (!glass || !glass.isVisible || !glass.ignoresMouseEvents || !screen) exit(21);
                NSRect visible=screen.visibleFrame;
                BOOL expectedRight=NSMidX(pet.panel.frame)<=NSMidX(visible);
                CGFloat edge=expectedRight?NSMaxX(glass.frame):NSMinX(glass.frame);
                if (fabs(edge-(expectedRight?NSMaxX(visible):NSMinX(visible)))>1) exit(21);
                double started=[[pet valueForKey:@"activityStart"] doubleValue];
                double flight=[[pet valueForKey:@"smashFlight"] doubleValue];
                [pet setValue:@(started-flight-.1) forKey:@"activityStart"];
                [NSApp sendAction:NSSelectorFromString(@"tick:") to:pet from:nil];
                if ([[glass.contentView valueForKey:@"impactProgress"] doubleValue]<0) exit(21);
                [pet summon:nil];
                if ([pet valueForKey:@"glassPanel"] || glass.isVisible) exit(21);
                NSLog(@"Glass opposite-edge placement, impact and cancellation verified.");
            }
            NSBitmapImageRep *preview=[podcastView bitmapImageRepForCachingDisplayInRect:podcastView.bounds];
            [podcastView cacheDisplayInRect:podcastView.bounds toBitmapImageRep:preview];
            NSString *path=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:outingFiles[i]];
            if(![[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES])exit(21);
        }
        [pet summon:nil];
        if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && !NSProcessInfo.processInfo.lowPowerModeEnabled){
            pet.roaming=YES;
            NSMutableSet *seen=[NSMutableSet set];
            for(NSUInteger attempt=0;attempt<128 && seen.count<6;attempt++){
                [pet summon:nil];[pet setValue:@0 forKey:@"nextWander"];
                [NSApp sendAction:NSSelectorFromString(@"tick:") to:pet from:nil];
                id value=pet.panel.contentView.accessibilityValue;
                if(value)[seen addObject:value];
                if(value && !pet.casualSpeech && pet.effects.message)exit(21);
                pet.roaming=NO;
                if(pet.panel.contentView.accessibilityValue)exit(21);
                pet.roaming=YES;
            }
            if(seen.count!=6)exit(21);
        }
        [pet setSuspended:YES];
        NSLog(@"Manual and roaming pet activities, quote settings and click-to-wake verified.");
        pet.skippingEnabled=NO;pet.skipLimit=7;pet.speechEnabled=NO;pet.casualSpeech=YES;
        PebblePetController *restored=[[PebblePetController alloc] initWithDefaults:defaults];
        if(restored.skippingEnabled || restored.speechEnabled || !restored.casualSpeech || restored.skipLimit!=7)exit(20);
        [restored invalidate];
        PebblePetEffects *effects=[PebblePetEffects new];
        if(![effects showMessage:@"提醒展示接口" priority:PebblePetMessageReminder duration:5] ||
           [effects showMessage:@"闲聊" priority:PebblePetMessageAmbient duration:5] || ![effects.message isEqual:@"提醒展示接口"])exit(20);
        NSScreen *screen=NSScreen.screens.firstObject;
        NSRect visible=screen?screen.visibleFrame:NSMakeRect(0,0,1440,900);
        NSRect anchor=NSMakeRect(NSMidX(visible)-80,NSMinY(visible)+100,160,140);
        [effects updateAtTime:CACurrentMediaTime() anchor:anchor visible:visible];
        if(!effects.bubblePanel.isVisible || !effects.bubblePanel.ignoresMouseEvents || effects.bubblePanel.canBecomeKeyWindow ||
            !NSContainsRect(visible,effects.bubblePanel.frame))exit(20);
        NSView *bubble=effects.bubblePanel.contentView;
        NSBitmapImageRep *bubblePNG=[bubble bitmapImageRepForCachingDisplayInRect:bubble.bounds];
        [bubble cacheDisplayInRect:bubble.bounds toBitmapImageRep:bubblePNG];
        NSString *bubblePath=[[self.testPreviewPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pet-bubble-verification.png"];
        if(![[bubblePNG representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:bubblePath atomically:YES])exit(20);
        for(NSUInteger i=0;i<10;i++)[effects addRippleAt:NSMakePoint(NSMidX(visible),NSMinY(visible)+40) color:NSColor.systemTealColor];
        NSUInteger expectedRipples=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion?0:6;
        if(effects.rippleCount!=expectedRipples)exit(20);
        for(NSDictionary *entry in [effects valueForKey:@"ripples"]){
            NSPanel *panel=entry[@"panel"];
            if(panel.opaque || !panel.ignoresMouseEvents || !panel.isVisible || panel.canBecomeKeyWindow)exit(20);
        }
        if(expectedRipples){
            [effects updateAtTime:CACurrentMediaTime()+.25 anchor:anchor visible:visible];
            NSPanel *ringPanel=[effects valueForKey:@"ripples"][0][@"panel"];
            NSView *ring=ringPanel.contentView;
            NSBitmapImageRep *rep=[ring bitmapImageRepForCachingDisplayInRect:ring.bounds];
            [ring cacheDisplayInRect:ring.bounds toBitmapImageRep:rep];BOOL painted=NO;
            for(NSInteger y=0;y<rep.pixelsHigh;y++)for(NSInteger x=0;x<rep.pixelsWide;x++)if([rep colorAtX:x y:y].alphaComponent>.02)painted=YES;
            if(!painted)exit(20);
        }
        [effects updateAtTime:CACurrentMediaTime()+40 anchor:anchor visible:visible];
        if(effects.message || effects.bubblePanel.isVisible || effects.rippleCount)exit(20);
        [effects showMessage:@"测试关闭" priority:PebblePetMessageInteraction duration:5];effects.speechEnabled=NO;
        if(effects.message || [effects showMessage:@"不得显示" priority:PebblePetMessageReminder duration:5])exit(20);
        [effects clear];
        BOOL oldPreview=self.settingsPreview;NSInteger oldPass=self.shotPassNumber;
        self.settingsPreview=YES;self.shotPassNumber=2;[self buildSettings];
        self.settingsPreview=oldPreview;self.shotPassNumber=oldPass;
        if(self.panes.count!=5 || ![self.sectionButtons[PetPaneIndex].title isEqual:@"桌宠"] ||
           ![self.petSwitch isDescendantOf:self.panes[PetPaneIndex]] || [self.petSwitch isDescendantOf:self.panes[GeneralPaneIndex]] ||
           ![self.sectionButtons[PassPaneIndex].title isEqual:@"石头证"] || ![self.sectionButtons[AboutPaneIndex].title isEqual:@"关于"])exit(20);
        [self showPaneAtIndex:PetPaneIndex];if(self.selectedSettingsPane!=PetPaneIndex)exit(20);
        NSLog(@"Pet tab routing, horizontal gesture skipping, preferences, speech priority/bounds/expiry/disable and ripple teardown verified.");
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
