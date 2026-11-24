#import <AppKit/AppKit.h>

typedef struct { NSPoint position; NSPoint velocity; BOOL resting; } PebblePetBody;
FOUNDATION_EXPORT NSRect PebblePetConstrainFrame(NSRect frame, NSRect visible);
FOUNDATION_EXPORT NSPoint PebblePetThrowVelocity(NSPoint gesture, NSSize size);
FOUNDATION_EXPORT PebblePetBody PebblePetAdvance(PebblePetBody body, NSRect visible, NSSize size, double elapsed);
FOUNDATION_EXPORT NSDictionary *PebblePetPlacement(NSRect frame, NSScreen *screen);
FOUNDATION_EXPORT NSRect PebblePetRestoreFrame(id placement, NSArray<NSScreen *> *screens, NSSize size);

typedef struct {
    PebblePetBody body;
    double waterline;
    double hop;
    NSUInteger bounces,limit;
    BOOL active,sliding;
    NSPoint impactPosition;
} PebblePetSkip;
FOUNDATION_EXPORT BOOL PebblePetShouldSkip(NSPoint velocity);
FOUNDATION_EXPORT PebblePetSkip PebblePetBeginSkip(PebblePetBody body, NSRect visible, NSSize size, NSUInteger limit);
FOUNDATION_EXPORT PebblePetSkip PebblePetAdvanceSkip(PebblePetSkip skip, NSRect visible, NSSize size, double elapsed);
FOUNDATION_EXPORT NSRect PebblePetBubbleFrame(NSRect anchor, NSRect visible, NSSize size);
