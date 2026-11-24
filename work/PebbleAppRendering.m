#import "PebbleAppInternal.h"

@implementation PebbleApp (Rendering)

- (WKWebView *)newRendererForDesktop:(BOOL)desktop {
    return [self newRendererWithConfig:self.rendererConfigScript desktop:desktop];
}

- (NSString *)rendererVerificationInstrumentation {
    return @"window.pebbleVerifyIntervalTicks=0;window.pebbleVerifyIntervals=new Set();"
             "{const start=window.setInterval.bind(window),stop=window.clearInterval.bind(window);"
             "window.setInterval=(fn,ms,...args)=>{const id=start(()=>{"
             "window.pebbleVerifyIntervalTicks++;fn(...args)},ms);"
             "window.pebbleVerifyIntervals.add(id);return id};"
             "window.clearInterval=id=>{window.pebbleVerifyIntervals.delete(id);stop(id)}};";
}

- (WKWebView *)newRendererWithConfig:(NSString *)config desktop:(BOOL)desktop {
    if (self.testPreviewPath) config = [config stringByAppendingString:self.rendererVerificationInstrumentation];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    // The first pebble is raised while the module loads, so the choice has to be
    // in place before any of the bundle runs.
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:config
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    if (desktop) {
        WKUserScript *showQuestion = [[WKUserScript alloc]
            initWithSource:@"document.documentElement.classList.add('pebble-desktop')"
             injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [configuration.userContentController addUserScript:showQuestion];
        [configuration.userContentController addScriptMessageHandler:self name:PebbleToneMessage];
        [configuration.userContentController addScriptMessageHandler:self name:@"pebbleHistory"];
    }
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    [self.rendererRecovery setObject:[PebbleRendererRecovery new] forKey:web];
    web.navigationDelegate = self;
    NSURL *page = [NSBundle.mainBundle URLForResource:@"wallpaper" withExtension:@"html"];
    [web loadFileURL:page allowingReadAccessToURL:page];
    return web;
}

- (void)placeDesktopControlOnScreen:(NSScreen *)screen display:(NSNumber *)display {
    NSRect screenFrame = screen.frame;
    // Match the question's desktop CSS and align the button with the end of the last line.
    CGFloat questionWidth = MIN(226, NSWidth(screenFrame) * .30);
    CGFloat questionRight = MIN(56, MAX(24, NSWidth(screenFrame) * .037));
    CGFloat questionBottom = 52 + questionWidth * 169 / 226;
    CGFloat buttonRight = questionRight + questionWidth * 14 / 226;
    NSRect frame = NSMakeRect(round(NSMaxX(screenFrame) - buttonRight - DesktopControlWidth),
                              round(NSMaxY(screenFrame) - questionBottom - 6 - DesktopControlHeight),
                              DesktopControlWidth, DesktopControlHeight);
    NSPanel *panel = self.desktopControls[display];
    if (panel) {
        [panel setFrame:frame display:YES];
        return;
    }

    panel = [[NSPanel alloc] initWithContentRect:frame
                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                        backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"鹅卵石桌面控制";
    // Keep the button above Finder's desktop and below regular application windows.
    panel.level = CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorIgnoresCycle;
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.hidesOnDeactivate = NO;

    PebbleDesktopButton *button = [[PebbleDesktopButton alloc] initWithFrame:
        NSMakeRect(0, 0, DesktopControlWidth, DesktopControlHeight)];
    NSURL *labelURL = [NSBundle.mainBundle URLForResource:@"refresh-label" withExtension:@"png"];
    NSImage *label = [[NSImage alloc] initWithContentsOfURL:labelURL];
    label.size = NSMakeSize(DesktopControlWidth, DesktopControlHeight);
    label.template = YES;
    button.bordered = NO;
    button.image = label;
    button.contentTintColor = NSColor.clearColor;
    button.imageScaling = NSImageScaleNone;
    button.imagePosition = NSImageOnly;
    button.toolTip = @"重新抛一颗鹅卵石";
    button.accessibilityLabel = @"重新抛";
    button.target = self;
    button.action = @selector(rethrowDesktopButton:);
    panel.contentView = button;
    self.desktopControls[display] = panel;
    [panel orderFrontRegardless];
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"pebbleHistory"]) {
        NSWindow *window = message.webView.window;
        NSNumber *display = window.screen.deviceDescription[@"NSScreenNumber"];
        if (!self.testPreviewPath && message.frameInfo.mainFrame && display &&
            self.desktopWindows[display] == window && [message.body isKindOfClass:NSDictionary.class]) {
            NSDictionary *history = PebbleNormalizeHistory(message.body, self.stoneTextures);
            self.pebbleHistory[display.stringValue] = history;
            [NSUserDefaults.standardUserDefaults setObject:self.pebbleHistory forKey:PebbleHistoryKey];
            [self prepareRendererForReload:message.webView];
            [self syncPetStone];
        }
        return;
    }
    if (![message.name isEqualToString:PebbleToneMessage] ||
        ![message.body isKindOfClass:NSNumber.class]) return;
    NSWindow *wallpaper = message.webView.window;
    NSNumber *display = wallpaper.screen.deviceDescription[@"NSScreenNumber"];
    if (!display || self.desktopWindows[display] != wallpaper) return;
    NSUInteger tone = [message.body unsignedIntegerValue];
    if (tone > 0xFFFFFF) return;
    NSButton *button = (NSButton *)self.desktopControls[display].contentView;
    button.contentTintColor = [NSColor colorWithSRGBRed:((tone >> 16) & 255) / 255.0
                                               green:((tone >> 8) & 255) / 255.0
                                                blue:(tone & 255) / 255.0 alpha:1];
}

// These images must survive app replacement and moving the application bundle.
- (void)refreshDisplays:(NSNotification *)notification {
    [self syncNativeDesktopBackground:self.petOnlyMode];
    NSString *staticPath = [NSUserDefaults.standardUserDefaults stringForKey:StaticWallpaperPathKey];
    BOOL staticMode = !self.testPreviewPath && staticPath &&
                      [NSFileManager.defaultManager fileExistsAtPath:staticPath];
    self.staticWallpaperMode = staticMode;
    self.dynamicModeItem.state = !staticMode && !self.petOnlyMode;
    self.staticModeItem.state = staticMode;
    self.petOnlyModeItem.state = self.petOnlyMode;
    BOOL hideWallpaper = staticMode || self.petOnlyMode;
    NSMutableSet<NSNumber *> *connected = [NSMutableSet set];
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
        if (!display) continue;
        [connected addObject:display];
        NSWindow *window = self.desktopWindows[display];
        if (window) {
            [window setFrame:screen.frame display:YES];
            [self placeDesktopControlOnScreen:screen display:display];
            NSPanel *panel = self.desktopControls[display];
            if (hideWallpaper) {
                [window orderOut:nil];
                [panel orderOut:nil];
            } else {
                if (!window.isVisible) [window orderFrontRegardless];
                if (!panel.isVisible) [panel orderFrontRegardless];
            }
            continue;
        }
        window = [[NSWindow alloc] initWithContentRect:screen.frame
                                           styleMask:NSWindowStyleMaskBorderless
                                             backing:NSBackingStoreBuffered defer:NO];
        window.level = CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorStationary |
                                    NSWindowCollectionBehaviorIgnoresCycle;
        window.backgroundColor = [NSColor colorWithSRGBRed:238.0/255 green:238.0/255 blue:231.0/255 alpha:1];
        window.ignoresMouseEvents = YES;
        window.hasShadow = NO;
        window.hidesOnDeactivate = NO;
        NSString *config = self.rendererConfigScript;
        if (!self.testPreviewPath) {
            NSDictionary *history = self.pebbleHistory[display.stringValue] ?: @{};
            config = [config stringByAppendingFormat:@"window.pebbleHistory = %@;%@",
                      [self jsonForPebble:history], self.smartPauseScript];
        }
        window.contentView = [self newRendererWithConfig:config desktop:YES];
        self.desktopWindows[display] = window;
        if (!hideWallpaper) [window orderFrontRegardless];
        [self placeDesktopControlOnScreen:screen display:display];
        if (hideWallpaper) [self.desktopControls[display] orderOut:nil];
    }
    for (NSNumber *display in self.desktopWindows.allKeys) {
        if ([connected containsObject:display]) continue;
        [self.desktopWindows[display] orderOut:nil];
        [self.desktopWindows removeObjectForKey:display];
        [self.desktopControls[display] orderOut:nil];
        [self.desktopControls removeObjectForKey:display];
    }
    [self syncRendererStartupScripts];
    // Explicitly stop/start animation timers when entering/leaving static mode.
    // Hidden WebViews can stay alive for exports; visibility alone is not a pause.
    [self forEachRenderer:^(WKWebView *web) { [self applyPauseTo:web]; }];
    [self rebuildRethrowMenu];
    [self.pet refreshScreens];
    [self updatePetPresentation];
}

#pragma mark - Settings window

- (void)performWallpaperScript:(NSString *)script inWeb:(WKWebView *)web reportErrors:(BOOL)report
    completion:(void (^)(id, NSError *))completion {
    void (^finish)(id, NSError *) = ^(id result, NSError *error) {
        if (error) {
            NSLog(@"Wallpaper command failed: %@", error);
            if ([error.domain isEqual:WKErrorDomain] && error.code == WKErrorWebContentProcessTerminated)
                [self recoverRenderer:web error:error];
            if (report) [self showWallpaperError:[NSString stringWithFormat:@"画面可能正在加载或恢复，请稍后重试。也可从菜单栏选择「%@」。", ReloadWallpaperTitle]];
        }
        if (completion) completion(result, error);
    };
    if (!web) finish(nil, [NSError errorWithDomain:@"Pebble" code:1 userInfo:@{NSLocalizedDescriptionKey:@"屏幕已断开"}]);
    else [web evaluateJavaScript:script completionHandler:finish];
}

- (void)syncRendererStartupScripts {
    [self forEachRenderer:^(WKWebView *web) { [self prepareRendererForReload:web]; }];
}

- (NSString *)smartPauseScript {
    BOOL enabled = ![NSUserDefaults.standardUserDefaults boolForKey:SmartPauseDisabledKey];
    BOOL paused = enabled && (self.screenLocked || self.displaysAsleep || self.sessionInactive ||
                             NSProcessInfo.processInfo.lowPowerModeEnabled);
    return [NSString stringWithFormat:@"window.pebbleSmartPaused = %@;", paused ? @"true" : @"false"];
}

- (void)observeSmartPause {
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSNotificationName name in @[NSWorkspaceScreensDidSleepNotification, NSWorkspaceScreensDidWakeNotification,
                                       NSWorkspaceSessionDidResignActiveNotification, NSWorkspaceSessionDidBecomeActiveNotification,
                                       NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification]) {
        [workspace addObserver:self selector:@selector(smartPauseChanged:) name:name object:nil];
    }
    NSDistributedNotificationCenter *distributed = NSDistributedNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[@"com.apple.screenIsLocked", @"com.apple.screenIsUnlocked"]) {
        [distributed addObserver:self selector:@selector(smartPauseChanged:) name:name object:nil
              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(smartPauseChanged:)
        name:NSProcessInfoPowerStateDidChangeNotification object:nil];
}

- (void)smartPauseChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *name = notification.name;
        if ([name isEqualToString:@"com.apple.screenIsLocked"]) self.screenLocked = YES;
        if ([name isEqualToString:@"com.apple.screenIsUnlocked"]) self.screenLocked = NO;
        if ([name isEqualToString:NSWorkspaceScreensDidSleepNotification]) self.displaysAsleep = YES;
        if ([name isEqualToString:NSWorkspaceScreensDidWakeNotification]) self.displaysAsleep = NO;
        if ([name isEqualToString:NSWorkspaceSessionDidResignActiveNotification]) self.sessionInactive = YES;
        if ([name isEqualToString:NSWorkspaceSessionDidBecomeActiveNotification]) self.sessionInactive = NO;
        [self syncRendererStartupScripts];
        [self updatePetPresentation];
        [self forEachRenderer:^(WKWebView *web) { [self applyPauseTo:web]; }];
    });
}

- (void)toggleSmartPause:(NSMenuItem *)sender {
    BOOL disabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:disabled forKey:SmartPauseDisabledKey];
    sender.state = disabled ? NSControlStateValueOff : NSControlStateValueOn;
    [self smartPauseChanged:nil];
}

- (void)forEachRenderer:(void (^)(WKWebView *))action {
    for (NSWindow *window in self.desktopWindows.allValues) action((WKWebView *)window.contentView);
    // The pass stone is deliberately absent: it must never follow these choices.
}

- (void)rebuildRethrowMenu {
    [self.rethrowMenu removeAllItems]; [self.previousMenu removeAllItems]; [self.exportMenu removeAllItems];
    [self addItem:@"所有屏幕" action:@selector(changePebble:) toMenu:self.rethrowMenu];
    [self addItem:@"所有屏幕" action:@selector(previousPebble:) toMenu:self.previousMenu];
    for (NSNumber *display in self.connectedDisplayIdentifiers) {
        NSString *title = [self displayTitle:display];
        [self addItem:title action:@selector(rethrowMenuScreen:) toMenu:self.rethrowMenu].representedObject = display;
        [self addItem:title action:@selector(previousPebble:) toMenu:self.previousMenu].representedObject = display;
    }
    for (NSUInteger index=0; index<WallpaperSizeCount; index++) {
        WallpaperExportSize size=WallpaperSizes[index];
        NSMenuItem *entry=[self.exportMenu addItemWithTitle:[NSString stringWithFormat:@"%@（%lu × %lu）",size.name,(unsigned long)size.width,(unsigned long)size.height] action:nil keyEquivalent:@""];
        NSMenu *screens=[[NSMenu alloc] initWithTitle:entry.title]; entry.submenu=screens;
        for (NSNumber *display in self.connectedDisplayIdentifiers) {
            NSMenuItem *item=[self addItem:[[self displayTitle:display] stringByAppendingString:@"…"] action:@selector(exportWallpaper:) toMenu:screens];
            item.tag=index; item.representedObject=display;
        }
    }
}

- (void)rethrowDisplay:(NSNumber *)display {
    NSWindow *window = display ? self.desktopWindows[display] : nil;
    if (!window || (!window.isVisible && !self.petPreview)) return;
    [self performWallpaperScript:@"window.pebbleThrow()" inWeb:(WKWebView *)window.contentView reportErrors:YES completion:nil];
}

- (void)rethrowMenuScreen:(NSMenuItem *)sender {
    [self rethrowDisplay:sender.representedObject];
}

- (void)rethrowDesktopButton:(NSButton *)sender {
    [self.desktopControls enumerateKeysAndObjectsUsingBlock:^(NSNumber *display, NSPanel *panel, BOOL *stop) {
        if (panel == sender.window) {
            [self rethrowDisplay:display];
            *stop = YES;
        }
    }];
}

- (void)changePebble:(id)sender {
    for (NSNumber *display in self.desktopWindows) [self rethrowDisplay:display];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if(item.action==@selector(skipPet:))return self.pet.stoneImage && self.pet.skippingEnabled;
    if(item.action==@selector(sayPet:))return self.pet.stoneImage && self.pet.speechEnabled;
    if(item.action==@selector(syncPetStone) || item.action==@selector(togglePetRoaming:)) return self.pet!=nil;
    if (item.action == @selector(previousPebble:)) {
        for (NSNumber *display in PebbleTargetDisplays(self.connectedDisplayIdentifiers, item.representedObject, YES))
            if (self.desktopWindows[display].isVisible && self.pebbleHistory[display.stringValue][@"previous"]) return YES;
        return NO;
    }
    if (item.action == @selector(rethrowMenuScreen:)) {
        return self.desktopWindows[item.representedObject].isVisible;
    }
    if (item.action == @selector(changePebble:)) {
        for (NSWindow *window in self.desktopWindows.allValues) {
            if (window.isVisible) return YES;
        }
        return NO;
    }
    return YES;
}

- (void)applyPauseTo:(WKWebView *)web {
    NSString *script = [NSString stringWithFormat:
        @"window.pebblePaused = %@; window.pebbleStaticPaused = %@; %@ "
         "document.dispatchEvent(new Event('visibilitychange'));",
        self.paused ? @"true" : @"false",
        self.staticWallpaperMode ? @"true" : @"false", self.smartPauseScript];
    [self performWallpaperScript:script inWeb:web reportErrors:NO completion:nil];
}

- (void)togglePause:(id)sender {
    // The switch has already flipped by the time it calls us; the menu item has not.
    self.paused = [sender isKindOfClass:NSSwitch.class] ?
        ((NSSwitch *)sender).state == NSControlStateValueOff : !self.paused;
    [NSUserDefaults.standardUserDefaults setBool:self.paused forKey:PausedPreference];
    self.pauseItem.state = self.paused ? NSControlStateValueOff : NSControlStateValueOn;
    [self syncSettingsControls];
    [self syncRendererStartupScripts];
    [self forEachRenderer:^(WKWebView *web) { [self applyPauseTo:web]; }];
}

- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))reply {
    NSURL *page = [NSBundle.mainBundle URLForResource:@"wallpaper" withExtension:@"html"];
    reply([action.request.URL isEqual:page] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

// Recover the same view so screen ownership, controls and the pass layout stay intact.
- (BOOL)prepareRendererForReload:(WKWebView *)web {
    NSString *config = nil;
    BOOL desktop = NO;
    for (NSNumber *display in self.desktopWindows) {
        if (self.desktopWindows[display].contentView != web) continue;
        desktop = YES;
        config = [self.rendererConfigScript stringByAppendingFormat:
            @"window.pebbleHistory = %@;%@window.pebblePaused = %@;",
            [self jsonForPebble:self.pebbleHistory[display.stringValue] ?: @{}],
            self.smartPauseScript, self.paused ? @"true" : @"false"];
        break;
    }
    if (web == self.passRenderer) config = self.passConfigScript;
    if (!config) return NO; // A disconnected display's delayed retry is obsolete.
    WKUserContentController *controller = web.configuration.userContentController;
    [controller removeAllUserScripts];
    if (desktop) config = [config stringByAppendingString:
        @"document.documentElement.classList.add('pebble-desktop');"];
    if (self.testPreviewPath) config = [config stringByAppendingString:self.rendererVerificationInstrumentation];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:config
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    return YES;
}

- (void)recoverRenderer:(WKWebView *)web error:(NSError *)error {
    PebbleRendererRecovery *state = [self.rendererRecovery objectForKey:web];
    if (!state || state.pending) return;
    if (state.attempts >= 3) {
        NSLog(@"Renderer recovery stopped after three attempts: %@. Use %@ to retry.", error, ReloadWallpaperTitle);
        return;
    }
    state.pending = YES;
    NSUInteger generation = ++state.generation;
    NSTimeInterval delay = 1 << state.attempts++;
    NSLog(@"Renderer interrupted (%@); retry %lu in %.0fs.", error,
        (unsigned long)state.attempts, delay);
    __weak WKWebView *weakWeb = web;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WKWebView *view = weakWeb;
        if (!view || generation != state.generation) return;
        state.pending = NO;
        if (![self prepareRendererForReload:view]) return;
        NSURL *page = [NSBundle.mainBundle URLForResource:@"wallpaper" withExtension:@"html"];
        [view loadFileURL:page allowingReadAccessToURL:page];
    });
}

- (void)reloadRenderers:(id)sender {
    NSMutableArray *views = [NSMutableArray array];
    for (NSWindow *window in self.desktopWindows.allValues) [views addObject:window.contentView];
    if (self.passRenderer) [views addObject:self.passRenderer];
    for (WKWebView *web in views) {
        PebbleRendererRecovery *state = [self.rendererRecovery objectForKey:web];
        state.pending = NO;
        state.attempts = 0;
        state.generation++;
        [self recoverRenderer:web error:nil];
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web {
    [self recoverRenderer:web error:[NSError errorWithDomain:WKErrorDomain
        code:WKErrorWebContentProcessTerminated userInfo:nil]];
}

- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled && [error.domain isEqual:NSURLErrorDomain]) return;
    [self recoverRenderer:web error:error];
}

- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:web didFailProvisionalNavigation:navigation withError:error];
}

- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    PebbleRendererRecovery *state = [self.rendererRecovery objectForKey:web];
    NSUInteger generation = state.generation;
    // A page that repeatedly loads then crashes must still exhaust its retry budget.
    __weak WKWebView *weakWeb = web;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (weakWeb && state.generation == generation && !state.pending) state.attempts = 0;
    });
    if (web != self.passRenderer) [self performWallpaperScript:
        [self.rendererConfigScript stringByAppendingString:@"window.pebbleRedraw?.();"]
        inWeb:web reportErrors:NO completion:nil];
    [self applyPauseTo:web];
    if (web != self.passRenderer) [self syncPetStone];
    if (self.testPreviewPath && self.verificationReload) {
        void (^loaded)(WKWebView *) = self.verificationReload; self.verificationReload = nil; loaded(web); return;
    }
    if (self.verifyingRecovery && web == self.desktopWindows.allValues.firstObject.contentView) {
        [self checkRecoveredRenderer:web attempt:0];
    } else if (self.testPreviewPath && web == self.desktopWindows.allValues.firstObject.contentView) {
        [self verifyRenderer:web attempt:0];
    }
}

// A broken override still draws perfectly good stones, it just ignores the
// menu, so check every link: the saved choices reach the page, a choice pins
// what it promises, and clearing it lets the renderer vary again instead of
// leaving the last choice stuck.
@end
