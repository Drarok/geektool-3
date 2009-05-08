//
//  LogController.m
//  GeektoolPreferencePane
//
//  Created by Kevin Nygaard on 3/18/09.
//  Copyright 2009 AllocInit. All rights reserved.
//

#import "LogController.h"
#import "GeekToolPrefs.h"

NSString *MovedRowsType = @"GTLog_Moved_Item";
NSString *CopiedRowsType = @"GTLog_Copied_Item";


@implementation LogController

- (void)awakeFromNib
{
    // register for drag and drop
    
	[tableView setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[tableView setDraggingSourceOperationMask:(NSDragOperationCopy | NSDragOperationMove) forLocal:YES];
	
	[tableView registerForDraggedTypes:
    [NSArray arrayWithObjects:CopiedRowsType, MovedRowsType, nil]];
    [tableView setAllowsMultipleSelection:YES];
	
	[super awakeFromNib];
}

- (void)addObject:(id)object
{
    // save only once
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:YES];
    [super addObject:object];
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
    [preferencesController savePrefs];
}

- (void)remove:(id)object
{
    // save only once
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:YES];
    [super remove:object];
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
    [preferencesController savePrefs];
}

// thank you mr mmalc, you fixed my setClearsFilterPredicateOnInsertion: problem

#pragma mark Methods
- (IBAction)duplicateLog:(id)sender
{
    // just in case this gets called with nothing selected...
    if ([self selectionIndex] != NSNotFound)
    {
        // get our selection (potentially multiple items)
        NSArray *selectedObjects = [self selectedObjects];
        NSEnumerator *e = [selectedObjects objectEnumerator];
        
        GTLog *currentLog = nil;
        GTLog *copyLog = nil;
        
        // loop for however many items in the set
        while (currentLog = [e nextObject])
        {
            copyLog = [currentLog copy];
            // TODO: localize
            // TODO: make the renaming algo more fluid (like how Finder handles duplicate names)
            [copyLog setName:[NSString stringWithFormat: @"%@ %@", [copyLog name],@"copy"]];
            [self addObject:copyLog];
            [copyLog release];
        }
    }
}

- (IBAction)addLog:(id)sender
{
    NSString *currentGroupString = [currentActiveGroup titleOfSelectedItem];
    GTLog *toAdd = [[GTLog alloc]init];
    [toAdd setGroup:currentGroupString];
    
    [self addObject:toAdd];
    [toAdd release];
    [preferencesController savePrefs];
}


#pragma mark Drag n' Drop Stuff
// thanks to mmalc for figuring most of this stuff out for me (and just being amazing)
- (BOOL)tableView:(NSTableView *)aTableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
	 toPasteboard:(NSPasteboard *)pboard
{
	// declare our own pasteboard types
    NSArray *typesArray = [NSArray arrayWithObjects:MovedRowsType, nil];
		
    [pboard declareTypes:typesArray owner:self];
	
    // add rows array for local move
	NSData *rowIndexesArchive = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard setData:rowIndexesArchive forType:MovedRowsType];
	
	// create new array of selected rows for remote drop
    // could do deferred provision, but keep it direct for clarity
	NSMutableArray *rowCopies = [NSMutableArray arrayWithCapacity:[rowIndexes count]];
	
    unsigned int currentIndex = [rowIndexes firstIndex];
    while (currentIndex != NSNotFound)
    {
		[rowCopies addObject:[[self arrangedObjects] objectAtIndex:currentIndex]];
        currentIndex = [rowIndexes indexGreaterThanIndex: currentIndex];
    }
	
	// setPropertyList works here because we're using dictionaries, strings,
	// and dates; otherwise, archive collection to NSData...
	[pboard setPropertyList:rowCopies forType:CopiedRowsType];
	
    return YES;
}


- (NSDragOperation)tableView:(NSTableView*)tv
				validateDrop:(id <NSDraggingInfo>)info
				 proposedRow:(int)row
	   proposedDropOperation:(NSTableViewDropOperation)op
{
    
    NSDragOperation dragOp = NSDragOperationCopy;
    
    // if drag source is self, it's a move unless the Option key is pressed
    if ([info draggingSource] == tableView) {
			dragOp =  NSDragOperationMove;
    }
    // we want to put the object at, not over,
    // the current row (contrast NSTableViewDropOn) 
    [tv setDropRow:row dropOperation:NSTableViewDropAbove];
	
    return dragOp;
}

- (BOOL)tableView:(NSTableView*)tv
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(int)row
	dropOperation:(NSTableViewDropOperation)op
{
    BOOL result = NO;
    
    // we need to suspend our saving for a little bit because moveObjectInArrangedObjectsFromIndexes:toIndex: hits it when it removes/adds objects
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:YES];
    if (row < 0) {
		row = 0;
	}
	// if drag source is self, it's a move unless the Option key is pressed
    if ([info draggingSource] == tableView) {
        NSData *rowsData = [[info draggingPasteboard] dataForType:MovedRowsType];
        NSIndexSet *indexSet = [NSKeyedUnarchiver unarchiveObjectWithData:rowsData];
        
        NSIndexSet *destinationIndexes = [self moveObjectsInArrangedObjectsFromIndexes:indexSet toIndex:row];
        // set selected rows to those that were just moved
        [self setSelectionIndexes:destinationIndexes];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                   rowsData,@"indexSet",
                                   [NSNumber numberWithInt: row],@"row",
                                   nil];
        [preferencesController logReorder:userInfo];
        
        result = YES;
    }
    
    [[NSDistributedNotificationCenter defaultCenter] setSuspended:NO];
    [preferencesController savePrefs];
    
    return result;
}

-(NSIndexSet *) moveObjectsInArrangedObjectsFromIndexes:(NSIndexSet*)fromIndexSet
												toIndex:(unsigned int)insertIndex
{	
	// If any of the removed objects come before the insertion index,
	// we need to decrement the index appropriately
	unsigned int adjustedInsertIndex =
	insertIndex - [fromIndexSet countOfIndexesInRange:(NSRange){0, insertIndex}];
	NSRange destinationRange = NSMakeRange(adjustedInsertIndex, [fromIndexSet count]);
	NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
	
	NSArray *objectsToMove = [[self arrangedObjects] objectsAtIndexes:fromIndexSet];
	[self removeObjectsAtArrangedObjectIndexes:fromIndexSet];	
	[self insertObjects:objectsToMove atArrangedObjectIndexes:destinationIndexes];
	
	return destinationIndexes;
}

- (id)selectedObject
{
    int selectionIndex = [self selectionIndex];       
    if (selectionIndex != NSNotFound)
        return [[self selectedObjects] objectAtIndex:0];
    else
        return nil;
}

@end

#pragma mark -
#pragma mark Quick helper method
/*
 Implementation of NSIndexSet utility category
 */
@implementation NSIndexSet (CountOfIndexesInRange)

-(unsigned int)countOfIndexesInRange:(NSRange)range
{
	unsigned int start, end, count;
	
	if ((start == 0) && (range.length == 0))
	{
		return 0;	
	}
	
	start	= range.location;
	end		= start + range.length;
	count	= 0;
	
	unsigned int currentIndex = [self indexGreaterThanOrEqualToIndex:start];
	
	while ((currentIndex != NSNotFound) && (currentIndex < end))
	{
		count++;
		currentIndex = [self indexGreaterThanIndex:currentIndex];
	}
	
	return count;
}
@end
