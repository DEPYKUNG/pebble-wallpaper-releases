#import "PebbleAppInternal.h"

NSImage *PebbleMenuBarIcon(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 16) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSBezierPath *stone = [NSBezierPath bezierPath];
        [stone moveToPoint:NSMakePoint(1, 6.3)];
        [stone curveToPoint:NSMakePoint(6.5, 11.9)
              controlPoint1:NSMakePoint(1, 9) controlPoint2:NSMakePoint(3.3, 10.7)];
        [stone curveToPoint:NSMakePoint(11.8, 13.5)
              controlPoint1:NSMakePoint(8.9, 12.8) controlPoint2:NSMakePoint(10.2, 13.5)];
        [stone curveToPoint:NSMakePoint(17, 6.5)
              controlPoint1:NSMakePoint(14.9, 13.5) controlPoint2:NSMakePoint(17, 9.5)];
        [stone curveToPoint:NSMakePoint(9, 2.5)
              controlPoint1:NSMakePoint(17, 3.3) controlPoint2:NSMakePoint(13.6, 2.5)];
        [stone curveToPoint:NSMakePoint(1, 6.3)
              controlPoint1:NSMakePoint(4.1, 2.5) controlPoint2:NSMakePoint(1, 3.4)];
        [stone closePath];

        // Cut out the eyes so they stay legible when AppKit tints the template.
        stone.windingRule = NSWindingRuleEvenOdd;
        [stone appendBezierPathWithOvalInRect:NSMakeRect(5.7, 6, 2.1, 3.4)];
        [stone appendBezierPathWithOvalInRect:NSMakeRect(10.2, 6, 2.1, 3.4)];
        [NSColor.blackColor setFill];
        [stone fill];
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = WallpaperTitle;
    return image;
}
