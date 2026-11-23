#import "PebbleAppInternal.h"

@implementation PebbleApp (Updates)

#if __has_include(<Sparkle/Sparkle.h>)
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item
    immediateInstallationBlock:(void (^)(void))install {
#ifdef PEBBLE_UPDATE_TEST
    // Logged so the loopback harness can assert against the same path production takes.
    NSLog(@"Verified update %@ ready to install.", item.versionString);
#endif
    // The wallpaper is a login agent that users never quit, so waiting for
    // termination could strand them on an old build for weeks. Install right
    // away instead; Sparkle relaunches the wallpaper with no interface shown.
    [self stageUpdateInstallation:install];
    return YES;
}

- (void)stageUpdateInstallation:(void (^)(void))install {
    self.pendingInstall = install;
    self.installationRequested = NO;
#ifdef PEBBLE_UPDATE_TEST
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--defer-update-test"]) {
        [self showSettings:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            if (self.installationRequested || !self.pendingInstall) exit(11);
            NSLog(@"Update deferred while settings are open; closing settings now.");
            [self.settings close];
        });
    }
#endif
    // Sparkle may only use the handler after this delegate has returned YES.
    dispatch_async(dispatch_get_main_queue(), ^{ [self installPendingUpdateIfIdle]; });
}

// Relaunching while the interactive window is open would discard it mid-use.
- (void)installPendingUpdateIfIdle {
    if (!self.pendingInstall || self.installationRequested || self.settings.isVisible) return;
    self.installationRequested = YES;
    void (^install)(void) = self.pendingInstall;
    install();
    // An application or system service can cancel termination. Keep the handler
    // so closing settings or the next idle opportunity can retry, without looping.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (self.pendingInstall == install) self.installationRequested = NO;
    });
}

- (void)resetPendingUpdate {
    self.pendingInstall = nil;
    self.installationRequested = NO;
}

- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    [self resetPendingUpdate];
    NSLog(@"Update aborted: %@", error);
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check
    error:(NSError *)error {
    [self resetPendingUpdate];
}

- (void)settingsDidClose:(NSNotification *)notification {
    // NSWindowWillClose arrives before isVisible changes.
    dispatch_async(dispatch_get_main_queue(), ^{ [self installPendingUpdateIfIdle]; });
}
#endif

#if __has_include(<Sparkle/Sparkle.h>)
- (void)toggleAutomaticChecks:(NSSwitch *)sender {
    self.updaterController.updater.automaticallyChecksForUpdates =
        sender.state == NSControlStateValueOn;
}

- (void)toggleAutomaticInstall:(NSSwitch *)sender {
    self.updaterController.updater.automaticallyDownloadsUpdates =
        sender.state == NSControlStateValueOn;
}
#endif

@end
