/*
 * PushrNetUtil.m
 * --------------
 *
 * Author: Chris Lee <clee@mg8.org>
 * License: GPL v2 <http://www.opensource.org/licenses/gpl-license.php>
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PushrNetUtil.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <ifaddrs.h>

@implementation PushrNetUtil

- (id)initWithPushr: (MobilePushr *)pushr
{
	if (![super init]) {
		return nil;
	}

	_pushr = [pushr retain];
	_activeInterfaceNames = [[NSMutableArray alloc] initWithCapacity: 0];

	struct ifaddrs *first_ifaddr, *current_ifaddr;
	getifaddrs(&first_ifaddr);
	current_ifaddr = first_ifaddr;
	while (current_ifaddr != NULL) {
		if (current_ifaddr->ifa_addr->sa_family == 0x02)
			[_activeInterfaceNames addObject: [NSString stringWithFormat: @"%s", current_ifaddr->ifa_name]];
		current_ifaddr = current_ifaddr->ifa_next;
	}
	freeifaddrs(first_ifaddr);
	
	return self;	
}

- (void)dealloc
{
	[_activeInterfaceNames release];
	[_pushr release];
	[super dealloc];
}

- (void)warnUserAboutSlowEDGE
{
	UIAlertSheet *alertSheet = [[UIAlertSheet alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 320.0f, 240.0f)];
	[alertSheet setTitle: @"This might take a while"];
	[alertSheet setBodyText: @"You don't seem to have an active WiFi connection, and pushing photos over EDGE is really slow. Still want to push over EDGE?"];
	[alertSheet addButtonWithTitle: @"Push over EDGE"];
	[alertSheet addButtonWithTitle: @"Try again later"];
	[alertSheet setDelegate: self];
	[alertSheet setRunsModal: YES];
	[alertSheet popupAlertAnimated: YES];
}

- (void)drownWithoutNetwork
{
	UIAlertSheet *alertSheet = [[UIAlertSheet alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 320.0f, 240.0f)];
	[alertSheet setTitle: @"No network available"];
	[alertSheet setBodyText: @"Pushr doesn't work if it can't talk to Flickr, and right now, no network connections are active."];
	[alertSheet addButtonWithTitle: @"Try again later"];
	[alertSheet setDelegate: _pushr];
	[alertSheet setRunsModal: YES];
	[alertSheet popupAlertAnimated: YES];
}

- (void) alertSheet: (UIAlertSheet *)sheet buttonClicked: (int)button
{
	[sheet dismiss];
	[sheet release];

	switch (button) {
		case 1: {
			NSLog(@"Told the user EDGE was slow, but they want to push anyway...");
			break;
		}
		default: {
			[_pushr terminate];
			break;
		}
	}
}

- (NSArray *)activeInterfaceNames
{
	return [NSArray arrayWithArray: _activeInterfaceNames];
}

- (BOOL)hasWiFi
{
	NSArray *activeInterfaces = [self activeInterfaceNames];
	return [activeInterfaces containsObject: @"en0"] || [activeInterfaces containsObject: @"en1"];
}

- (BOOL)hasEDGE
{
	NSArray *activeInterfaces = [self activeInterfaceNames];
	return [activeInterfaces containsObject: @"ip0"] || [activeInterfaces containsObject: @"ip1"];
}

@end