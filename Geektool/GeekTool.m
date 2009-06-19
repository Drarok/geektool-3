#import "GeekTool.h"
#import "LogWindow.h"
#import "LogWindowController.h"

@implementation GeekTool
- (void)awakeFromNib
{
    // notice here, we are going to use NSUserDefaults instead of the carbon crap
    // this is because this module is not a prefpane, and hence, easy to work with
    
    // This array will store the tunnels descriptions and windows/tasks references
    g_logs = [[NSMutableArray alloc] init];
    
    // We register for some preferencePane notifications
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(prefsNotification:)
                                                            name: nil
                                                          object: @"GeekToolPrefs"
                                              suspensionBehavior: NSNotificationSuspensionBehaviorCoalesce];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidChangeScreenParameters:)
                                                 name: @"NSApplicationDidChangeScreenParametersNotification"
                                               object: nil];
    
    // Good, now publish the fact we are running, in case preferencePane is launched
    [self notifyLaunched];
    
    highlighted = -1;
    
    //[self loadDefaults];
    [self updateWindows: NO];    
    [self setDelegate: self];
}

- (void)notifyLaunched
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTLaunched"
                                                                   object: @"GeekTool"
                                                                 userInfo: nil
                                                       deliverImmediately: YES]; 
}

// This method handles all notifications sent by the preferencePane
-(void)prefsNotification:(NSNotification*)aNotification
{
    if ([[aNotification name] isEqualTo: @"GTUpdateWindows"]) // Preferences changed, update
        [self updateWindows: NO];
    
    if ([[aNotification name] isEqualTo: @"GTForceUpdateWindows"]) // Preferences changed, update
        [self updateWindows: YES];
    
    else if ([[aNotification name] isEqualTo: @"GTPrefsLaunched"]) // Preferences here, show it
    {
        // Tell preferencePane we are here too
        [self notifyLaunched];
    }
    
    else if ([[aNotification name] isEqualTo: @"GTPrefsQuit"])
    {
        // if something is highlighted, that means that it is able to be moved around
        if (highlighted > -1)
        {
            [g_logs makeObjectsPerformSelector:@selector(setHighlighted:) withObject:NO];
            highlighted = -1;
        }
    }
    
    else if ([[aNotification name] isEqualTo: @"GTQuit"])
    {
        // Checkbox has been unchecked, quit
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTQuitOK"
                                                                       object: @"GeekTool"
                                                                     userInfo: nil
                                                           deliverImmediately: YES];
        
        [[NSApplication sharedApplication] terminate: self];
    }
    
    else if ([[aNotification name] isEqualTo: @"GTHighlightWindow"])
    {
        // check to make sure that the group is part of the active group
        if ([[[aNotification userInfo] objectForKey: @"groupName"] isEqualTo:
             [[NSUserDefaults standardUserDefaults] objectForKey: @"currentGroup"]])
        {
            int index = [[[aNotification userInfo] objectForKey: @"index"] intValue];
           
            // make all logs non-highlighted
            [g_logs makeObjectsPerformSelector:@selector(setHighlighted:) withObject:NO];
            
            // make the log at index highlighted
            if (index > -1)
                [[g_logs objectAtIndex: index] setHighlighted: YES];
            
            highlighted = index;
        }
        else
        {
            if (highlighted > -1)
            {
                [g_logs makeObjectsPerformSelector:@selector(setHighlighted:) withObject:NO];
                highlighted = -1;
            }
        }
        [self reorder];
    }
    else if ([[aNotification name] isEqualTo: @"GTReorder"])
    {
        NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
        [indexSet addIndexes:[NSKeyedUnarchiver unarchiveObjectWithData:[[aNotification userInfo]objectForKey:@"indexSet"]]];
        int row = [[[aNotification userInfo]objectForKey:@"row"]intValue];
        
        // TODO: maybe can consolidate this with the extremely similar function in LogController.m
        unsigned int adjustedInsertIndex =
        row - [indexSet countOfIndexesInRange:(NSRange){0, row}];
        NSRange destinationRange = NSMakeRange(adjustedInsertIndex, [indexSet count]);
        NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
        
        NSArray *objectsToMove = [g_logs objectsAtIndexes:indexSet];
        [g_logs removeObjectsAtIndexes:indexSet];	
        [g_logs insertObjects:objectsToMove atIndexes:destinationIndexes];

        [g_logs makeObjectsPerformSelector:@selector(setHighlighted:) withObject:NO];
        [self updateWindows:NO];
        [self reorder];
    }
    else if ([[aNotification name] isEqualTo: @"GTTransparency"])
    {
        if (highlighted != -1)
        {
            float tr = [[[aNotification userInfo] objectForKey: @"transparency"] floatValue];
            [[g_logs objectAtIndex: highlighted] setTransparency: tr];
        }
    }
}

- (void)reorder
{
    NSEnumerator *e = [g_logs reverseObjectEnumerator];
    GTLog *log = nil;
    while (log = [e nextObject])
        [log front];
}

// This method is responsible of reading preferences and initiliaze the g_logs array
- (void)updateWindows:(BOOL)force
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSUserDefaults resetStandardUserDefaults];
        
    // This tmp array stores preferences dictionary "as is"
    NSString *currentGroup = [[NSUserDefaults standardUserDefaults] objectForKey:@"currentGroup"];
    NSArray *logs = [[NSUserDefaults standardUserDefaults] objectForKey:@"logs"];
    
    if (logs == nil ) logs = [NSArray array];
    
    // We parse all logs to see if something changed.
    // We add log entries if there are new, and we delete some that could have been
    // deleted in prefs
    
    unsigned int i = 0;
    
    for (NSDictionary *logD in logs)
    {
        // make sure to load only windows that are in the active group
        if (![[logD valueForKey: @"group"] isEqual: currentGroup])
            continue;
        
        // use previously existing logs (ie don't allocate anything new)
        if (i < [g_logs count])
        {
            GTLog *currentLog = [g_logs objectAtIndex: i];
            [currentLog setDictionary: logD force: force];
        }
        
        // make new logs
        else
        {
            GTLog *log = [[GTLog alloc] initWithDictionary: logD];
            [g_logs addObject: log];
            [log createWindow];
            [log release];
        }
        i++;        
    }  
    // Remove all logs upon the count in preferences
    // (those have been deleted)
    while ([g_logs count] > i)
    {
        [[g_logs lastObject] terminate];
        [g_logs removeLastObject];
    }
    
    logs = nil;
    
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTUpdateMenu"
                                                                   object: @"GeekTool"
                                                                 userInfo: nil
                                                       deliverImmediately: YES];
    [pool release];
    
    if (highlighted > -1)
        [[ g_logs objectAtIndex: highlighted ] setHighlighted: YES ];
    [self reorder];
}

// magnetic windows enabled if the command key is held down
- (void)flagsChanged:(NSEvent*)event
{
    if ([event modifierFlags] & NSCommandKeyMask)
    {
        magn = YES;
        xGuides = [[NSMutableArray array] retain];
        yGuides = [[NSMutableArray array] retain];
        NSArray *screens = [NSScreen screens];
        
        [yGuides addObject: [NSNumber numberWithFloat: [[NSScreen mainScreen] frame].size.height - 22]];
        for (NSScreen *screen in screens)
        {
            [xGuides addObject: [NSNumber numberWithFloat: [screen frame].origin.x]];
            [xGuides addObject: [NSNumber numberWithFloat: [screen frame].origin.x + [screen frame].size.width]];
            [yGuides addObject: [NSNumber numberWithFloat: [screen frame].origin.y]];
            [yGuides addObject: [NSNumber numberWithFloat: [screen frame].origin.y + [screen frame].size.height]];
        }
    }
    else
    {
        magn = NO;
        [xGuides release];
        xGuides = nil;
        [yGuides release];
        yGuides = nil;
    }
}
- (BOOL)magn
{
    return magn;
}
- (NSMutableArray*)xGuides
{
    return xGuides;
}
- (NSMutableArray*)yGuides
{
    return yGuides;
}
// Argh, who changed screen settings ????
- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification
{
    [self updateWindows: YES];
}

// Cleanup
- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    
    for (GTLog *log in g_logs)
        [log terminate];
}

// We have to terminate tasks before quitting
-(void)dealloc
{
    [g_logs release];
    [super dealloc];
}
@end