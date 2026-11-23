#import <AppKit/AppKit.h>

typedef struct { NSPoint position; NSPoint velocity; BOOL resting; } PebblePetBody;
FOUNDATION_EXPORT NSRect PebblePetConstrainFrame(NSRect frame, NSRect visible);
FOUNDATION_EXPORT PebblePetBody PebblePetAdvance(PebblePetBody body, NSRect visible, NSSize size, double elapsed);
FOUNDATION_EXPORT NSDictionary *PebblePetPlacement(NSRect frame, NSScreen *screen);
FOUNDATION_EXPORT NSRect PebblePetRestoreFrame(id placement, NSArray<NSScreen *> *screens, NSSize size);
