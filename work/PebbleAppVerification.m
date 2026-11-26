#import "PebbleAppInternal.h"

@implementation PebbleApp (Verification)

- (void)verifyChoicesReachPage:(WKWebView *)web then:(void (^)(void))next {
    // The saved choices arrive through a document-start user script, a path no
    // amount of JavaScript testing covers. Check it before overwriting them.
    [web evaluateJavaScript:@"[window.pebbleConfig.texture, window.pebbleConfig.palette,"
                             " window.pebbleConfig.faces]"
          completionHandler:^(NSArray *injected, NSError *read) {
        NSArray *expected = @[self.texture ?: (id)NSNull.null, self.palette ?: (id)NSNull.null,
                              self.face ?: (id)NSNull.null];
        if (read || ![injected isKindOfClass:NSArray.class] || ![injected isEqualToArray:expected]) {
            NSLog(@"Saved choices %@ did not reach the page (got %@)", expected, injected);
            exit(7);
        }
        [self verifyOverrides:web then:next];
    }];
}

- (void)verifyOverrides:(WKWebView *)web then:(void (^)(void))next {
    NSString *script =
        @"(() => {const button = document.querySelector('button');"
         "window.pebbleHistory = null;"
         "const raise = count => Array.from({length: count}, () => {button.click();"
         " return {texture: window.pebbleTexture, palette: window.pebblePalette,"
         "         base: window.pebbleColors[0]};});"
         "const channels = stone => [1, 3, 5].map(at => parseInt(stone.base.substr(at, 2), 16));"
         "window.pebbleConfig.texture = 'rings'; window.pebbleConfig.palette = null;"
         "const ringed = raise(5);"
         "window.pebbleConfig.texture = null; window.pebbleConfig.palette = 'red';"
         "const reds = raise(5);"
         "window.pebbleConfig.palette = 'blue'; const blues = raise(5);"
         "window.pebbleConfig.palette = 'gray'; const greys = raise(5);"
         "window.pebbleConfig.palette = null; const free = raise(20);"
         // Only about a third of stones carry a face of their own, so compare
         // all three modes of the same stone and key the expectation off the
         // recovered seed rather than hoping the sample happens to cover both.
         "const canvas = document.querySelector('canvas');"
         "const shot = mode => {window.pebbleConfig.faces = mode;"
         " window.pebbleRedraw(); return canvas.toDataURL();};"
         "const faced = Array.from({length: 5}, () => {button.click();"
         " const seededFace = window.pebbleFaceRoll < .35;"
         " return {seededFace, seeded: shot(null), on: shot('on'), off: shot('off')};});"
         "window.pebbleConfig.faces = null; window.pebbleRedraw();"
         // A pinned seed has to reproduce the same stone, and clearing it has to
         // let the renderer wander again, or the pass would drift or be frozen.
         "window.pebbleConfig.seed = 123456;"
         "button.click(); const stampA = canvas.toDataURL();"
         "button.click(); const stampB = canvas.toDataURL();"
         "delete window.pebbleConfig.seed;"
         "button.click(); const looseA = canvas.toDataURL();"
         "button.click(); const looseB = canvas.toDataURL();"
         "const originalTilt = window.pebbleConfig.tiltDegrees;"
         "window.pebbleConfig.tiltDegrees = -30; window.pebbleRedraw();"
         "const tiltedLeft = canvas.toDataURL();"
         "window.pebbleConfig.tiltDegrees = 30; window.pebbleRedraw();"
         "const tiltedRight = canvas.toDataURL();"
         "window.pebbleConfig.tiltDegrees = originalTilt; window.pebbleRedraw();"
         "const originalRate = window.pebbleConfig.rotationRate, originalTimer = window.setInterval;"
         "const originalSmartPause = window.pebbleSmartPaused;"
         "window.pebbleSmartPaused = false;"
         "let delay; window.setInterval = (callback, interval) => { delay = interval; return 0; };"
         "const schedule = rate => { delay = undefined; window.pebbleConfig.rotationRate = rate;"
         " document.dispatchEvent(new Event('visibilitychange')); return delay; };"
         "Object.defineProperty(document, 'hidden', {configurable:true, value:false});"
         "window.pebblePaused = false;"
         "const normal = schedule(1), slow = schedule(.5), fast = schedule(2);"
         "window.pebblePaused = true; const paused = schedule(2);"
         "window.pebblePaused = false; window.pebbleSmartPaused = true;"
         "const smartPaused = schedule(2); window.pebbleSmartPaused = false;"
         "const resumed = schedule(2); window.pebblePaused = true;"
         "const manuallyPaused = schedule(2);"
         "delete document.hidden; window.setInterval = originalTimer;"
         "window.pebbleSmartPaused = originalSmartPause;"
         "window.pebbleConfig.rotationRate = originalRate;"
         "const restoredTiltFrame = canvas.toDataURL();"
         "window.pebbleHistory = {};"
         "Object.assign(window.pebbleConfig, {seed:111, texture:'rings', palette:'red', faces:'on'});"
         "window.pebbleThrow(); const saved = JSON.stringify(window.pebbleHistory.current);"
         "const savedFrame = canvas.toDataURL();"
         "Object.assign(window.pebbleConfig, {seed:222, texture:'stripes', palette:'blue', faces:'off'});"
         "window.pebbleThrow(); const second = JSON.stringify(window.pebbleHistory.current);"
         "window.pebblePrevious(); const previousMatches = canvas.toDataURL() === savedFrame"
         " && JSON.stringify(window.pebbleHistory.current) === saved"
         " && JSON.stringify(window.pebbleHistory.previous) === second;"
         "window.pebbleThrow(); window.pebbleRestore(JSON.parse(saved));"
         "const restoredMatches = canvas.toDataURL() === savedFrame"
         " && JSON.stringify(window.pebbleHistory.current) === saved;"
         "const pose=JSON.parse(saved);pose.yaw=1.2;pose.pitch=.3;window.pebbleRestore(pose);"
         "const poseRestored=JSON.stringify(window.pebbleSnapshot())===JSON.stringify(pose) && canvas.toDataURL()!==savedFrame;"
         "const legacy=JSON.parse(saved);delete legacy.schemaVersion;delete legacy.yaw;delete legacy.pitch;"
         "window.pebbleRestore(legacy);const migrated=window.pebbleSnapshot();"
         "const legacyRestored=migrated.schemaVersion===1 && migrated.yaw===0 && migrated.pitch===-.12;"
         "window.pebbleHistory = null;"
         "return {seedPinned: stampA === stampB, seedReleased: looseA !== looseB,"
         " previousMatches, restoredMatches, poseRestored, legacyRestored,"
         " smartPause: smartPaused === undefined && resumed === fast && manuallyPaused === undefined,"
         " tiltApplied: tiltedLeft !== tiltedRight && looseB === restoredTiltFrame,"
         " speedApplied: normal > 0 && slow === normal * 2 && fast === normal / 2 && paused === undefined,"
         " facesForced: faced.every(stone => stone.on !== stone.off),"
         " facesMatchSeed: faced.every(stone =>"
         "   (stone.seeded !== stone.off) === stone.seededFace),"
         " texturePinned: ringed.every(stone => stone.texture === 'rings'),"
         " textureReleased: free.some(stone => stone.texture !== 'rings'),"
         " redIsWarm: reds.every(stone => {const [r, g, b] = channels(stone); return r > g && r > b;}),"
         " blueIsCool: blues.every(stone => {const [r, g, b] = channels(stone); return b > r && b > g;}),"
         " greyIsNeutral: greys.every(stone => {const [r, g, b] = channels(stone); return r === g && g === b;}),"
         " familyVaries: new Set(reds.map(stone => stone.base)).size > 1,"
         " paletteTagged: reds.every(stone => stone.palette === 'red'),"
         " paletteReleased: free.every(stone => stone.palette === null)};})()";
    [web evaluateJavaScript:script completionHandler:^(NSDictionary *result, NSError *error) {
        if (error || ![result isKindOfClass:NSDictionary.class]) {
            NSLog(@"Could not check the renderer overrides: %@", error);
            exit(6);
        }
        NSMutableArray<NSString *> *failed = [NSMutableArray array];
        for (NSString *check in result) {
            if (![result[check] boolValue]) [failed addObject:check];
        }
        if (failed.count) {
            NSLog(@"Renderer overrides failed: %@", [failed componentsJoinedByString:@", "]);
            exit(6);
        }
        next();
    }];
}

- (void)verifyBackgroundPicker:(WKWebView *)web then:(void (^)(void))next {
    [self backgroundPicker];
    NSString *original = self.backgroundPreset;
    [web callAsyncJavaScript:
        @"const frame = () => { window.pebbleRedraw(); return document.querySelector('canvas').toDataURL(); };"
         "return {preset: document.documentElement.dataset.pebbleBackground, frame: frame()};"
        arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(NSDictionary *before, NSError *error) {
            if (error || ![before[@"preset"] isEqual:original]) exit(8);
            [self verifyBackgroundAtIndex:0 initialFrame:before[@"frame"] web:web then:^{
                for (NSButton *choice in self.backgroundButtons) {
                    if ([original isEqual:@(BackgroundKeys[choice.tag])]) {
                        [choice performClick:nil];
                        break;
                    }
                }
                NSLog(@"All eight backgrounds applied without replacing the stone.");
                next();
            }];
        }];
}

- (void)verifyBackgroundAtIndex:(NSUInteger)index initialFrame:(NSString *)frame
                            web:(WKWebView *)web then:(void (^)(void))next {
    if (index == BackgroundCount) {
        next();
        return;
    }
    [self.backgroundButtons[index] performClick:nil];
    NSString *read = @"window.pebbleRedraw(); ({frame: document.querySelector('canvas').toDataURL(),"
                     "preset: document.documentElement.dataset.pebbleBackground,"
                     "color: getComputedStyle(document.body).backgroundColor,"
                     "texture: getComputedStyle(document.body).backgroundImage !== 'none'})";
    [web evaluateJavaScript:read completionHandler:^(NSDictionary *result, NSError *error) {
        NSUInteger rgb = BackgroundColors[index];
        NSString *color = [NSString stringWithFormat:@"rgb(%lu, %lu, %lu)",
            (unsigned long)((rgb >> 16) & 255), (unsigned long)((rgb >> 8) & 255), (unsigned long)(rgb & 255)];
        NSString *asset = [@"background-" stringByAppendingString:@(BackgroundKeys[index])];
        BOOL expectedTexture = [NSBundle.mainBundle URLForResource:asset withExtension:@"jpg"] != nil;
        if (error || [result[@"texture"] boolValue] != expectedTexture || ![result[@"preset"] isEqual:@(BackgroundKeys[index])] ||
            ![result[@"color"] isEqual:color] || ![result[@"frame"] isEqual:frame]) exit(8);
        [self verifyBackgroundAtIndex:index + 1 initialFrame:frame web:web then:next];
    }];
}

- (void)verifyPhoneWallpaperSizes:(WKWebView *)web {
    NSMutableArray *sizes = [NSMutableArray array];
    for (NSUInteger index = 1; index < WallpaperSizeCount; index++) {
        [sizes addObject:@[@(WallpaperSizes[index].width), @(WallpaperSizes[index].height)]];
    }
    [web callAsyncJavaScript:
        @"for (const [width, height] of sizes) {"
         " const image = new Image();"
         " image.src = 'data:image/png;base64,' + window.pebbleExport(width, height);"
         " await image.decode();"
         " if (image.naturalWidth !== width || image.naturalHeight !== height) return false;"
         "} return true;"
        arguments:@{@"sizes":sizes} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(NSNumber *verified, NSError *error) {
            if (error || !verified.boolValue) {
                NSLog(@"Phone wallpaper size verification failed: %@", error);
                exit(9);
            }
            NSLog(@"Verified native PNG dimensions for all five iPhone export sizes.");
            [self verifyDisplayRoutingThen:^{ [self verifyStaticPause:web]; }];
        }];
}

- (void)verifyDisplayRoutingThen:(void (^)(void))next {
    NSArray *displays = self.connectedDisplayIdentifiers;
    if (!displays.count || self.exportMenu.numberOfItems != WallpaperSizeCount) exit(14);
    for (NSMenuItem *size in self.exportMenu.itemArray) {
        NSMutableArray *targets = [NSMutableArray array];
        for (NSMenuItem *item in size.submenu.itemArray) [targets addObject:item.representedObject];
        if (![targets isEqual:displays]) exit(14);
    }
    BOOL wasPaused = self.paused; self.paused = YES;
    [self forEachRenderer:^(WKWebView *web) { [self applyPauseTo:web]; }];
    dispatch_group_t group = dispatch_group_create();
    [displays enumerateObjectsUsingBlock:^(NSNumber *display, NSUInteger index, BOOL *stop) {
        dispatch_group_enter(group);
        NSString *script = [NSString stringWithFormat:
            @"window.pebbleHistory={};window.pebbleConfig.seed=%lu;window.pebbleThrow();window.pebbleConfig.seed=%lu;",
            (unsigned long)(100000+index), (unsigned long)(200000+index)];
        [(WKWebView *)self.desktopWindows[display].contentView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error) exit(14); dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSMenuItem *target = self.rethrowMenu.itemArray[1];
        [self rethrowMenuScreen:target];
        [self checkDisplaySeeds:displays rethrown:YES then:^{
            [self previousPebble:self.previousMenu.itemArray[1]];
            [self checkDisplaySeeds:displays rethrown:NO then:^{
                self.paused = wasPaused;
                [self forEachRenderer:^(WKWebView *web) { [self applyPauseTo:web]; }];
                NSLog(@"Per-screen rethrow/previous routing and all export menu targets verified on %lu screen(s).", (unsigned long)displays.count);
                self.staticWallpaperMode = YES;
                if (![self validateMenuItem:target]) exit(14);
                self.verifyStaticInstallation = ^(NSData *png, NSArray<NSScreen *> *screens) {
                    NSBitmapImageRep *image = [NSBitmapImageRep imageRepWithData:png];
                    if (image.pixelsWide != 3840 || image.pixelsHigh != 2160 || screens.count != 1 ||
                        ![screens.firstObject.deviceDescription[@"NSScreenNumber"] isEqual:target.representedObject]) exit(14);
                    self.verifyStaticInstallation = nil;
                    self.staticWallpaperMode = NO;
                    NSLog(@"Static menu rethrow exported 4K and routed to the selected display.");
                    next();
                };
                [self rethrowMenuScreen:target];
            }];
        }];
    });
}

- (void)checkDisplaySeeds:(NSArray *)displays rethrown:(BOOL)rethrown then:(void (^)(void))next {
    dispatch_group_t group = dispatch_group_create();
    [displays enumerateObjectsUsingBlock:^(NSNumber *display, NSUInteger index, BOOL *stop) {
        dispatch_group_enter(group);
        NSString *script = @"delete window.pebbleConfig.seed;window.pebbleSnapshot().seed";
        [(WKWebView *)self.desktopWindows[display].contentView evaluateJavaScript:script completionHandler:^(NSNumber *seed, NSError *error) {
            NSUInteger expected = index == 0 && rethrown ? 200000 : 100000+index;
            if (error || seed.unsignedIntegerValue != expected) exit(14);
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), next);
}

- (void)verifyStaticPause:(WKWebView *)web {
    BOOL paused = self.paused, staticMode = self.staticWallpaperMode;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *arguments = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *testArguments = [arguments mutableCopy] ?: [NSMutableDictionary dictionary];
    // Static pause must work even with smart pause disabled. This override is
    // process-local and never changes the user's stored preference.
    testArguments[SmartPauseDisabledKey] = @YES;
    [defaults setVolatileDomain:testArguments forName:NSArgumentDomain];
    [self verifyStaticPauseStep:0 web:web then:^{
        [defaults setVolatileDomain:arguments ?: @{} forName:NSArgumentDomain];
        self.paused = paused;
        self.staticWallpaperMode = staticMode;
        [self forEachRenderer:^(WKWebView *view) { [self applyPauseTo:view]; }];
        NSLog(@"Static mode stops animation timers even with smart pause disabled; manual pause and exports verified.");
        [self verifyRendererCommands:web];
    }];
}

- (void)verifyStaticPauseStep:(NSUInteger)step web:(WKWebView *)web then:(void (^)(void))next {
    if (step == 4) {
        [web evaluateJavaScript:@"delete document.hidden" completionHandler:nil];next(); return;
    }
    [web evaluateJavaScript:[NSString stringWithFormat:@"Object.defineProperty(document, 'hidden', {configurable:true,value:%@});",step==3?@"true":@"false"] completionHandler:nil];
    self.staticWallpaperMode = step == 0;
    self.paused = step == 1;
    [self forEachRenderer:^(WKWebView *view) { [self applyPauseTo:view]; }];
    [web callAsyncJavaScript:
        @"const before=window.pebbleVerifyIntervalTicks;"
         "await new Promise(resolve=>setTimeout(resolve,750));"
         "let exported=true;"
         "if(window.pebbleStaticPaused){const image=new Image();"
         "image.src='data:image/png;base64,'+window.pebbleExport(128,80);await image.decode();"
         "exported=image.naturalWidth===128&&image.naturalHeight===80;}"
         "return {before,after:window.pebbleVerifyIntervalTicks,"
         "active:window.pebbleVerifyIntervals.size,static:window.pebbleStaticPaused,"
         "manual:window.pebblePaused,smart:window.pebbleSmartPaused,exported,"
         "reduced:matchMedia('(prefers-reduced-motion: reduce)').matches,hidden:document.hidden};"
        arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(NSDictionary *result, NSError *error) {
        BOOL stopped = step < 2 || step==3 || [result[@"reduced"] boolValue];
        BOOL ticksStopped = [result[@"before"] isEqual:result[@"after"]];
        if (error || !result || [result[@"static"] boolValue] != (step == 0) ||
            [result[@"manual"] boolValue] != (step == 1) || [result[@"smart"] boolValue] ||
            ![result[@"exported"] boolValue] ||
            (stopped ? (!ticksStopped || [result[@"active"] integerValue] != 0)
                     : (ticksStopped || [result[@"active"] integerValue] != 1))) {
            NSLog(@"Static pause verification failed at step %lu: %@ %@", (unsigned long)step, result, error);
            exit(12);
        }
        [self verifyStaticPauseStep:step + 1 web:web then:next];
    }];
}

- (void)verifyRendererCommands:(WKWebView *)web {
    NSUInteger before = self.verificationCommandErrors;
    [self performWallpaperScript:@"window.pebbleDeliberatelyMissingVerificationFunction()" inWeb:web reportErrors:YES
        completion:^(id result, NSError *error) {
        if (!error || self.verificationCommandErrors != before + 1) exit(15);
        [web evaluateJavaScript:@"window.pebbleSnapshot()" completionHandler:^(NSDictionary *stone, NSError *readError) {
            if (readError || !PebbleNormalizeStone(stone, self.stoneTextures)) exit(15);
            NSNumber *display = web.window.screen.deviceDescription[@"NSScreenNumber"];
            NSInteger oldTilt=self.tiltDegrees; double oldRate=self.rotationRate; BOOL oldPaused=self.paused;
            id oldHistory=self.pebbleHistory[display.stringValue];
            self.pebbleHistory[display.stringValue]=@{@"current":stone};
            self.tiltDegrees=19; self.rotationRate=.5; self.paused=YES;
            [self syncRendererStartupScripts];
            __weak PebbleApp *weakSelf = self;
            self.verificationReload=^(WKWebView *loaded) {
                PebbleApp *app = weakSelf;
                [loaded callAsyncJavaScript:
                    @"for(let i=0;i<120&&!window.pebbleSnapshot;i++)await new Promise(r=>setTimeout(r,25));"
                     "return {tilt:window.pebbleConfig.tiltDegrees,rate:window.pebbleConfig.rotationRate,"
                     "paused:window.pebblePaused,stone:window.pebbleSnapshot()};"
                    arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
                    completionHandler:^(NSDictionary *value, NSError *loadError) {
                    if (loadError || [value[@"tilt"] integerValue]!=19 || [value[@"rate"] doubleValue]!=.5 ||
                        ![value[@"paused"] boolValue] || ![value[@"stone"] isEqual:stone]) exit(15);
                    app.tiltDegrees=oldTilt; app.rotationRate=oldRate; app.paused=oldPaused;
                    if (oldHistory) app.pebbleHistory[display.stringValue]=oldHistory;
                    else [app.pebbleHistory removeObjectForKey:display.stringValue];
                    [app syncRendererStartupScripts];
                    NSLog(@"Failed-command feedback and ordinary reload with latest settings/stone verified.");
                    [app verifyRendererRecovery:loaded];
                }];
            };
            [web reload];
        }];
    }];
}

// Exercise the production recovery path with the latest native settings, rather
// than merely checking that a delegate method exists. --verify never alters history.
- (void)verifyRendererRecovery:(WKWebView *)web {
    // Verification normally omits persistence; give the page an explicit stone.
    [web evaluateJavaScript:
        @"window.pebbleHistory={};window.pebbleThrow();window.pebbleHistory"
        completionHandler:^(NSDictionary *saved, NSError *readError) {
        if (readError || !saved[@"current"]) exit(10);
        NSNumber *display = web.window.screen.deviceDescription[@"NSScreenNumber"];
        self.pebbleHistory[display.stringValue] = saved;
        self.recoveryExpectedHistory = saved;
        self.tiltDegrees = 17;
        self.rotationRate = 1.5;
        self.paused = YES;
        self.verifyingRecovery = YES;
        [self webView:web didFailProvisionalNavigation:nil withError:
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
        if ([self.rendererRecovery objectForKey:web].attempts != 0) exit(10);
        [self webViewWebContentProcessDidTerminate:web];
        // Duplicate failures must coalesce into one pending retry.
        [self webView:web didFailNavigation:nil withError:
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];
        if ([self.rendererRecovery objectForKey:web].attempts != 1) exit(10);
    }];
}

- (void)checkRecoveredRenderer:(WKWebView *)web attempt:(NSUInteger)attempt {
    [web evaluateJavaScript:
        @"window.pebbleRedraw?.();({history:window.pebbleHistory,tilt:window.pebbleConfig.tiltDegrees,"
         "rate:window.pebbleConfig.rotationRate,paused:window.pebblePaused,"
         "ready:typeof window.pebbleTone==='number' && typeof window.pebbleThrow==='function'})"
        completionHandler:^(NSDictionary *result, NSError *error) {
        if (error || ![result[@"ready"] boolValue]) {
            if (attempt >= 40) exit(10);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{ [self checkRecoveredRenderer:web attempt:attempt + 1]; });
            return;
        }
        if (![result[@"history"] isEqual:self.recoveryExpectedHistory] ||
            [result[@"tilt"] integerValue] != 17 || [result[@"rate"] doubleValue] != 1.5 ||
            ![result[@"paused"] boolValue]) {
            NSLog(@"Recovered renderer lost state: %@", result); exit(10);
        }
        if (self.recoveryVerificationStage++ == 0) {
            [self webView:web didFailProvisionalNavigation:nil withError:
                [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotOpenFile userInfo:nil]];
            return;
        }
        PebbleRendererRecovery *state = [self.rendererRecovery objectForKey:web];
        if (self.recoveryVerificationStage == 3) {
            if (state.attempts != 1) exit(10);
            NSLog(@"Renderer recovery preserved stone/settings; cancellation, retry limit and manual retry verified.");
#if __has_include(<Sparkle/Sparkle.h>)
            [self verifyUpdateCallbackContract];
#else
            [NSApp terminate:nil];
#endif
            return;
        }
        state.attempts = 3;
        [self webViewWebContentProcessDidTerminate:web];
        if (state.pending || state.attempts != 3) exit(10);
        [self reloadRenderers:nil];
    }];
}

#if __has_include(<Sparkle/Sparkle.h>)
- (void)verifyUpdateCallbackContract {
    __block NSUInteger installs = 0;
    [self stageUpdateInstallation:^{ installs++; }];
    if (installs != 0) exit(11); // The delegate must return before invoking Sparkle.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (installs != 1 || !self.pendingInstall) exit(11);
        [self installPendingUpdateIfIdle];
        if (installs != 1) exit(11); // Coalesce duplicate close/idle notifications.
        [self resetPendingUpdate];
        if (self.pendingInstall || self.installationRequested) exit(11);
        [self stageUpdateInstallation:^{ installs++; }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (installs != 2) exit(11);
            [self resetPendingUpdate];
            if (self.pendingInstall || self.installationRequested) exit(11);
            NSLog(@"Update callback ordering, duplicate suppression and failed-cycle cleanup verified.");
            [self verifyPetUpdateDeferral];
        });
    });
}
#endif

- (void)verifyRenderer:(WKWebView *)web attempt:(NSUInteger)attempt {
    // Each draw clears the canvas. A nontransparent center confirms the offline texture rendered.
    NSString *readCanvas =
        @"(() => {const c = document.querySelector('canvas');"
         "if (!c || c.width !== c.height) return '';"
         "const gl = c.getContext('webgl'), pixel = new Uint8Array(4);"
         "gl.readPixels(c.width/2,c.height/2,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixel);"
         "return pixel[3] && typeof window.pebbleTone === 'number'"
         " ? {image:c.toDataURL(),tone:window.pebbleTone} : null;})()";
    NSString *pauseAndReadCanvas =
        [@"window.pebblePaused=true; document.dispatchEvent(new Event('visibilitychange'));"
         stringByAppendingString:readCanvas];
    [web evaluateJavaScript:pauseAndReadCanvas completionHandler:^(NSDictionary *first, NSError *error) {
        if (error || ![first isKindOfClass:NSDictionary.class]) {
            if (attempt >= 40) {
                NSLog(@"Wallpaper canvas did not render: %@", error);
                exit(1);
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{ [self verifyRenderer:web attempt:attempt + 1]; });
            return;
        }
        NSNumber *display = web.window.screen.deviceDescription[@"NSScreenNumber"];
        NSPanel *panel = display ? self.desktopControls[display] : nil;
        NSButton *button = (NSButton *)panel.contentView;
        if (!panel.isVisible || !button.isEnabled) exit(2);
        [button performClick:nil];
        [web evaluateJavaScript:readCanvas completionHandler:^(NSDictionary *second, NSError *readError) {
            if (readError || ![second isKindOfClass:NSDictionary.class] ||
                [first[@"image"] isEqual:second[@"image"]]) exit(2);
            NSColor *tint = [button.contentTintColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            NSUInteger buttonTone = (lround(tint.redComponent * 255) << 16) |
                                    (lround(tint.greenComponent * 255) << 8) |
                                     lround(tint.blueComponent * 255);
            if (tint.alphaComponent != 1 || buttonTone != [second[@"tone"] unsignedIntegerValue]) exit(5);
            WKSnapshotConfiguration *configuration = [WKSnapshotConfiguration new];
            configuration.snapshotWidth = @1280;
            [web takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image, NSError *snapshotError) {
                if (!image || snapshotError) exit(3);
                NSBitmapImageRep *buttonBitmap = [button bitmapImageRepForCachingDisplayInRect:button.bounds];
                [button cacheDisplayInRect:button.bounds toBitmapImageRep:buttonBitmap];
                NSImage *buttonImage = [[NSImage alloc] initWithSize:button.bounds.size];
                [buttonImage addRepresentation:buttonBitmap];

                NSRect desktopFrame = web.window.frame;
                CGFloat scale = image.size.width / NSWidth(desktopFrame);
                NSRect buttonRect = NSMakeRect((NSMinX(panel.frame) - NSMinX(desktopFrame)) * scale,
                                               (NSMinY(panel.frame) - NSMinY(desktopFrame)) * scale,
                                               NSWidth(panel.frame) * scale, NSHeight(panel.frame) * scale);
                NSImage *desktopPreview = [[NSImage alloc] initWithSize:image.size];
                [desktopPreview lockFocus];
                [image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
                [buttonImage drawInRect:buttonRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
                [desktopPreview unlockFocus];
                NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:desktopPreview.TIFFRepresentation];
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                if (![png writeToFile:self.testPreviewPath atomically:YES]) exit(4);
                [self verifyPetRenderer:web then:^{
                [self verifyChoicesReachPage:web then:^{
                    [self verifyBackgroundPicker:web then:^{
                        NSLog(@"Offline rendering, desktop button, matching text colors and "
                              "pinned texture and colour families verified.");
                        [web evaluateJavaScript:@"window.pebbleExport(3840,2160)" completionHandler:^(id encoded, NSError *error) {
                            NSData *png = [self wallpaperPNGFromBase64:encoded size:WallpaperSizes[0]];
                            NSBitmapImageRep *image = png ? [NSBitmapImageRep imageRepWithData:png] : nil;
                            NSColor *corner = [image colorAtX:0 y:0];
                            NSColor *center = [image colorAtX:1920 y:1080];
                            NSString *sample = [[self.testPreviewPath stringByDeletingLastPathComponent]
                                stringByAppendingPathComponent:@"wallpaper-4k-verification.png"];
                            if (error || !png || !center || [center isEqual:corner] ||
                                ![png writeToFile:sample atomically:YES]) {
                                NSLog(@"4K wallpaper render failed: %@", error);
                                exit(9);
                            }
                            for (NSUInteger index=1; index<WallpaperSizeCount; index++) {
                                 WallpaperExportSize size=WallpaperSizes[index];
                                 NSData *resized=[self resizeStaticWallpaperPNG:png size:size];
                                 NSBitmapImageRep *phone=resized ? [NSBitmapImageRep imageRepWithData:resized] : nil;
                                 if (phone.pixelsWide!=size.width || phone.pixelsHigh!=size.height ||
                                     [[phone colorAtX:size.width/2 y:(NSInteger)(size.height*.56)] isEqual:[phone colorAtX:0 y:0]]) exit(13);
                             }
                             NSLog(@"Saved static PNG exports preserve the stone for all phone sizes.");
                             NSLog(@"Verified 3840 × 2160 PNG with rendered stone and solid background.");
                            [self verifyPhoneWallpaperSizes:web];
                        }];
                    }];
                }];
                }];
            }];
        }];
    }];
}

@end
