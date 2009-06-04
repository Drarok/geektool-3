//
//  GeekToolPrefPref.m
//  GeekToolPref
//
//  Created by Yann Bizeul on Thu Nov 21 2002.
//  Copyright (c) 2002 __MyCompanyName__. All rights reserved.
//

#import <Carbon/Carbon.h>
#import "GeekToolPrefs.h"
#import "LogController.h"
#import "defines.h"

@implementation GeekToolPrefs

+ (void)initialize
{
    // Setting up our defaults here
    NSDictionary *defaults;
    defaults = [NSDictionary dictionaryWithObjectsAndKeys: 
                // General
                [NSArchiver archivedDataWithRootObject:[[NSColor alternateSelectedControlColor] colorWithAlphaComponent:0.3]], @"selectionColor",

                // Sparkle (auto updater)
                //[NSNumber numberWithInt:2], @"SUUpdate", // the selected tag in the popup box. SUScheduledCheckInterval derived from this value
                //[NSNumber numberWithLong:86400], @"SUScheduledCheckInterval", // daily
                
                nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

- (void)mainViewDidLoad
{
    // Register for some notifications
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applyAndNotifyNotification:)
                                                 name: NSControlTextDidEndEditingNotification
                                               object: nil];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(geekToolLaunched:)
                                                            name: @"GTLaunched"
                                                          object: @"GeekTool"
                                              suspensionBehavior: NSNotificationSuspensionBehaviorDeliverImmediately];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(geekToolQuit:)
                                                            name: @"GTQuitOK"
                                                          object: @"GeekTool"
                                              suspensionBehavior: NSNotificationSuspensionBehaviorDeliverImmediately];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(geekToolWindowChanged:)
                                                            name: @"GTWindowChanged"
                                                          object: @"GeekTool"
                                              suspensionBehavior: NSNotificationSuspensionBehaviorCoalesce];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(applyNotification:)
                                                            name: @"GTApply"
                                                          object: @"GeekTool"
                                              suspensionBehavior: NSNotificationSuspensionBehaviorDeliverImmediately];
    
    g_logs = nil;
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
    [self refreshLogsArray];
    [self refreshGroupsArray];
    
    // Yes, we need transparency
    [[NSColorPanel sharedColorPanel] setShowsAlpha: YES];
    
    NSNumber *en = [[NSUserDefaults standardUserDefaults] objectForKey: @"enableMenu"];
    if ([en boolValue]) [self loadMenu];    

    // load selection color data
    NSData *selectionColorData = [[NSUserDefaults standardUserDefaults] objectForKey: @"selectionColor"];
    if (!selectionColorData) selectionColorData = [NSArchiver archivedDataWithRootObject:[[NSColor alternateSelectedControlColor] colorWithAlphaComponent:0.3]];
    [self setSelectionColor:selectionColorData];
    
    [self initGroupsMenu];
    [self saveNotifications];
    //[self updatePanel];
}
                        
- (void)refreshLogsArray
{
    // this fn puts all logs into the structure below.
    // input is only from the "logs" preference
    // g_logs has the following structure
    /*
     g_logs (NSMutableDictionary)
        Group1 (key)
            log1 |
            log2 |-> (NSMutableArray)
            log3 |
            ...  |
        Group2 (key)
            log4 |
            log5 |-> (NSMutableArray)
            ...  |
        ... (key)
     end g_logs
     */
    
    // manage that memory!
    if (g_logs) [g_logs release];
    g_logs = [[NSMutableDictionary alloc]init];
    
    // load all log dictionaries into logsArray (dicts come from preferences
    // using these dictionaries, create the actual GTLog objects into g_logs.
    NSArray *logsArray = [[NSUserDefaults standardUserDefaults] objectForKey: @"logs"];
    
    NSEnumerator *e = [logsArray objectEnumerator];
    NSDictionary *gtDict = nil;
    GTLog *newLog = nil;
    
    while (gtDict = [e nextObject])
    {
        // make a new log
        newLog = [[GTLog alloc]initWithDictionary:gtDict];
        [self g_logsAddLog:newLog];
    }
}    

- (void)g_logsAddLog:(GTLog*)log
{    
    // check to see if this group has already been added in our data structure
    NSMutableArray *g_logsGroupArray = [g_logs objectForKey:[log group]];
    
    // if the group is already in our data structure, add to it
    if (g_logsGroupArray != nil)
    {
        [g_logsGroupArray addObject:log];
        [g_logs setObject:g_logsGroupArray forKey:[log group]];
    }
    // else, just make a new array to play with and stick it into g_logs
    else
    {
        g_logsGroupArray = [NSMutableArray arrayWithObject:log];
        [g_logs setObject:g_logsGroupArray forKey:[log group]];
    }
}

- (void)refreshGroupsArray
{
    // this fn puts all groups into the structure below
    // input is from the "groups" preference and logs in g_logs
    // groups has the following structure
    /*
     groups (NSMutableArray)
        obj1 (NSMutableDictionary)
            group (key)
            Group1 (NSString)
        obj2 (NSMutableDictionary)
             group (key)
             Group2 (NSString)
        ... (NSMutableDictionary)
     end groups
     */
    // load groups from our preferences
    NSArray *savedGroups = [[NSUserDefaults standardUserDefaults] objectForKey: @"groups"];
    
    // because we want to be able to do some fancy bindings for our table, we
    // need to store our groups as a dictionary of one value.
    // crude, i know, but working with NSStrings and NSArrays was simply not
    // working
    groups = [NSMutableArray array];
    NSEnumerator *e = [savedGroups objectEnumerator];
    NSString *tmpString = nil;
    
    // every item in the user preferences, make it a dictionary and pop it in the array
    // make sure it's mutable so we can rename it later on if we have to
    while (tmpString = [e nextObject])
    {
        [groups addObject:[NSMutableDictionary dictionaryWithObject:tmpString forKey:@"group"]];
    }
    
    // now we have the user's groups, time to put in necessary groups (ie groups
    // that the logs use, but may not have been saved in the preferences for
    // some reason)
    NSArray *g_logsKeys = [g_logs allKeys];
    e = [g_logsKeys objectEnumerator];
    NSMutableDictionary *tmpDict = nil;
    NSString *groupName = nil;
    
    while (groupName = [e nextObject])
    {
        tmpDict = [NSMutableDictionary dictionaryWithObject:groupName forKey:@"group"];
        if(![groups containsObject:tmpDict]) [groups addObject:tmpDict];
    }
    
    // if we have no groups at all, put in a default one for our lonely user
    // localize
    if ([groups count] <= 0) [groups addObject:[NSMutableDictionary dictionaryWithObject:@"Default" forKey:@"group"]];
    
    // let the binding magic begin
    [groupManager setContent:groups];  
}

- (void)saveNotifications
{
    // watch all these variables and run the observeValueForKeyPath function below each time any change
    [self addObserver:self forKeyPath:@"selectionColor" options:0 context:nil];
 	[logManager addObserver:self forKeyPath:@"arrangedObjects.enabled" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.name" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.type" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.enabled" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.group" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.fontName" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.fontSize" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.file" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.quartzFile" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.command" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.hide" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.refresh" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.textColor" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.backgroundColor" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.wrap" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.shadowText" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.shadowWindow" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.alignment" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.force" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.forceTitle" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.showIcon" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.pictureAlignment" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.imageURL" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.transparency" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.imageFit" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.x" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.y" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.w" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.h" options:0 context:nil];
    [logManager addObserver:self forKeyPath:@"arrangedObjects.alwaysOnTop" options:0 context:nil];
    
    // so we highlight logs if we can
    [logManager addObserver:self forKeyPath:@"selectedObjects" options:0 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // if the selection changes, highlight
    // anything else, just save
    if ([keyPath isEqualToString:@"selectedObjects"])
        [self notifyHighlight];
    else
        [self savePrefs];
}

- (NSMutableDictionary*)g_logs
{
    return g_logs;
}

#pragma mark -
#pragma mark UI management

- (IBAction)fileChoose:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setAllowsMultipleSelection: NO];
    [openPanel setCanChooseFiles: YES];
    [openPanel beginSheetForDirectory: @"/var/log/"
                                 file: @"system.log"
                                types: nil
                       modalForWindow: [[self mainView] window]
                        modalDelegate: self
                       didEndSelector: @selector(openPanelDidEnd:returnCode:contextInfo:)
                          contextInfo: nil];
}

- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [NSApp endSheet: sheet];
    if (returnCode == NSOKButton) {
        NSArray *filesToOpen = [sheet filenames];
        // TODO: write to path dictionary directly. bindings should take care of
        // this 
    }
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertDefaultReturn)
        [sheet close];
}

- (IBAction)groupsSheetClose:(id)sender
{
    // close the sheet and refresh our menu
    // note that -initGroupsMenu takes care of the "customize groups..." selection
    [NSApp stopModal];
    [self initGroupsMenu];
}

-(IBAction)gChooseFont:(id)sender
{
    // TODO: bindings maybe?
    /*
     switch ([self logType])
     {
     case 0:
     [[[self mainView] window] makeFirstResponder: cf1FontTextField];
     break;
     case 1:
     [[[self mainView] window] makeFirstResponder: cf2FontTextField];
     break;
     }
     [[NSFontManager sharedFontManager] orderFrontFontPanel: self];
     */
}

- (IBAction)selectedGroupChanged:(id)sender
{
    // update current content with g_logs
    [self g_logsUpdate];
    
    // the below will trigger unnecessary saves, so ignore saves for that part
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:YES];
    
    // switch manager content
    [logManager setContent:[g_logs objectForKey:[groupSelection titleOfSelectedItem]]];
    
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
    [self savePrefs];
}

#pragma mark -
#pragma mark Group Management
- (void)initGroupsMenu
{    
    /*
     Empty menu will look like this
     ____________________________
     |--------------------------| 0 Separator
     | Customize Groups...      | 1 Customize Groups item
     ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
     */
    
    // groupSelection and currentGroup are IB outlets to their respective elements
    // clear out everything that is there
    [groupSelection removeAllItems];
    [currentGroup removeAllItems];
    
    // make up our special static menu items via a menu (cant do it via NSPopUpButton)
    NSMenu *standardMenu = [[[NSMenu alloc] initWithTitle:@"StandardMenu"]autorelease];
    [standardMenu addItem:[NSMenuItem separatorItem]];
    // localize
    [standardMenu addItemWithTitle:@"Customize Groups..." action:nil keyEquivalent:@""];
    
    // refer to diagram above to see why this is at index 1
    // make the button do stuff. we couldn't combine it with the call above for
    // some reason (had to set target i think)
    NSMenuItem *customizeGroupsItem = [standardMenu itemAtIndex:1];
    [customizeGroupsItem setEnabled:TRUE];
    [customizeGroupsItem setAction:@selector(showGroupsCustomization)];
    [customizeGroupsItem setTarget:self]; 
    
    // commit our menu to the button
    [groupSelection setMenu:standardMenu];
    
    // put the groups into the popup buttons
    NSEnumerator *e = [groups reverseObjectEnumerator];
    NSDictionary *nextDict = nil;
    NSString *groupString = nil;
    
    // notice that we are inserting at index 0, giving stack-like (FILO) input
    // not really important, but remember if you want this sorted, you would have
    // to put it in reverse sorted (notice reverseObjectEnumerator was used
    // to give things a consistant feel of menus)
    while (nextDict = [e nextObject])
    {
        groupString = [nextDict valueForKey:@"group"];
        [groupSelection insertItemWithTitle:groupString atIndex:0];
        [currentGroup insertItemWithTitle:groupString atIndex:0];
    }
    
    // get everything selected right (don't want nil selections)
    NSString *currentGroupString = [[NSUserDefaults standardUserDefaults] objectForKey: @"currentGroup"];
    [currentGroup selectItemWithTitle:currentGroupString];
    [groupSelection selectItemAtIndex:0];
    
    // select something, you fool!
    if ([currentGroup selectedItem] == nil) [currentGroup selectItemAtIndex:0];
    
    // also, since we just selected something, make the log correct as well
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:YES];
    [logManager setContent:[g_logs objectForKey:[groupSelection titleOfSelectedItem]]];
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
}

- (void)showGroupsCustomization
{
    [NSApp beginSheet: groupsSheet
       modalForWindow: [[self mainView] window]
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
    [NSApp runModalForWindow: [[self mainView] window]];
    // Sheet is up here.
    [NSApp endSheet: groupsSheet];
    [groupsSheet orderOut: self];
}

#pragma mark -
#pragma mark Daemon interaction
- (void)didSelect
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTPrefsLaunched"
                                                                   object: @"GeekToolPrefs"
                                                                 userInfo: nil
                                                       deliverImmediately: YES];
    
}

- (void)geekToolWindowChanged:(NSNotification*)aNotification
{
    [[NSDistributedNotificationCenter defaultCenter] setSuspended: YES];
    NSDictionary *infos = [aNotification userInfo];
    [[logManager selectedObject] setX: [[infos objectForKey: @"x"] intValue]];
    [[logManager selectedObject] setY: [[infos objectForKey: @"y"] intValue]];
    [[logManager selectedObject] setW: [[infos objectForKey: @"w"] intValue]];
    [[logManager selectedObject] setH: [[infos objectForKey: @"h"] intValue]];
    [[NSDistributedNotificationCenter defaultCenter] setSuspended: NO];
    [self savePrefs];
}

- (void)geekToolLaunched:(NSNotification*)aNotification
{
    /*
     [gEnable setState: YES];
     */
     [self notifyHighlight];

}

- (void)updateWindows
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTUpdateWindows"
                                                                   object: @"GeekToolPrefs"
                                                                 userInfo: nil
                                                       deliverImmediately: NO];
}

- (void)logReorder:(NSDictionary*)userInfo
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTReorder"
                                                                   object: @"GeekToolPrefs"
                                                                 userInfo: userInfo
                                                       deliverImmediately: NO];
}

- (void)notifyHighlight
{
    int j = 0;
    
    // if the active and selected groups are not the same, we would not be able to highlight
    // any of the logs because they wouldn't be active
    if (![[currentGroup titleOfSelectedItem] isEqual: [groupSelection titleOfSelectedItem]])
        j = -1;
    
    // if nothing is selected, be sure to reflect that
    if ([logManager selectionIndex] == NSNotFound) 
        j = -1;
    
    // else, if something is selected, but it's group is not that of the active group
    else if (![[[[logManager selectedObjects]objectAtIndex:0]group] isEqual: [currentGroup titleOfSelectedItem]])
        j = -1;
    
    // get index of log to be highlighted
    else
    {
        j = [logManager selectionIndex];
    }
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [currentGroup titleOfSelectedItem], @"groupName",
                              [NSNumber numberWithInt: j], @"index",
                              nil];
    
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTHighlightWindow"
                                                                   object: @"GeekToolPrefs"
                                                                 userInfo: userInfo
                                                       deliverImmediately: YES];    
}

#pragma mark -
#pragma mark Preferences handling
- (void)g_logsUpdate
{
    NSArray *updatedLogs = [logManager content];
    NSString *group = [[updatedLogs lastObject]group];
    
    // handle nil
    if (group)
        [g_logs setObject:updatedLogs forKey:group];
}

- (void)savePrefs
{
    // becasue of our save notifiers, this method gets overcalled
    // by "gating" this, we can control when we want to save so we don't waste
    // (as much) time
    // sync our active log with g_logs so g_logs is current before saving
    [self g_logsUpdate];
    
    // when we do -allValues, we get an array of arrays. we would just like
    // all the values in one array, not multiple arrays
    NSArray *splinteredLogs = [g_logs allValues];
    NSMutableArray *allLogs = [NSMutableArray array];
    
    NSEnumerator *e = [splinteredLogs objectEnumerator];
    NSArray *tmpArray = nil;
    while (tmpArray = [e nextObject])
    {
        [allLogs addObjectsFromArray:tmpArray];
    }    
    
    
    NSMutableArray *logsArray = [NSMutableArray array];
    e = [allLogs objectEnumerator];
    GTLog *gtl = nil;
    
    while (gtl = [e nextObject])
    {
        [logsArray addObject: [gtl dictionary]];
    }
    
    NSMutableArray *groupsArray = [NSMutableArray array];
    e = [groups objectEnumerator];
    NSDictionary *tmpDict = nil;
    
    while (tmpDict = [e nextObject])
    {
        [groupsArray addObject: [tmpDict valueForKey:@"group"]];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[currentGroup titleOfSelectedItem] forKey:@"currentGroup"];
    [[NSUserDefaults standardUserDefaults] setObject:[self selectionColor] forKey:@"selectionColor"];
    [[NSUserDefaults standardUserDefaults] setObject:logsArray forKey:@"logs"];
    [[NSUserDefaults standardUserDefaults] setObject:groupsArray forKey:@"groups"];
    
    [self updateWindows];
}

- (void)setSelectionColor:(NSData *)var
{
    if(selectionColor != var)
    {
        [selectionColor release];
        selectionColor = [var copy];
    }
}

- (NSData*)selectionColor
{
    return selectionColor;
}

- (IBAction)gApply:(id)sender
{
    [self applyChanges];
    [self savePrefs];
    [self updateWindows];
}

- (IBAction)menuCheckBoxChanged:(id)sender
{
    if ([sender state])
    {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: YES] forKey: @"enableMenu"];
        [self loadMenu];
    }
    else
    {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: NO] forKey: @"enableMenu"];
        [self unloadMenu];
    }
}

#pragma mark -
#pragma mark Misc

- (NSRect)screenRect:(NSRect)oldRect
{
    NSRect screenSize = [[NSScreen mainScreen] frame];
    int screenY = screenSize.size.height - oldRect.origin.y - oldRect.size.height;
    return NSMakeRect(oldRect.origin.x, screenY, oldRect.size.width, oldRect.size.height);
}

- (void)didUnselect
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"GTPrefsQuit"
                                                                   object: @"GeekToolPrefs"
                                                                 userInfo: nil
                                                       deliverImmediately: YES];
    [[[NSFontManager sharedFontManager] fontPanel: NO] close];
}
@end
