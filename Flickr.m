/*
 * Flickr.m
 * --------
 * Class containing methods to interact with the Flickr web services. 
 *
 * Author: Chris Lee <clee@mg8.org>
 * License: GPL v2 <http://www.opensource.org/licenses/gpl-license.php>
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIAlertSheet.h>
#import "Flickr.h"
#import "MobilePushr.h"
#import "ExtendedAttributes.h"

#include <unistd.h>

@class NSXMLNode, NSXMLElement, NSXMLDocument;

@implementation Flickr

- (id)initWithPushr: (MobilePushr *)pushr
{
	if (![super init])
		return nil;

	_pushr = [pushr retain];
	_settings = [[NSUserDefaults standardUserDefaults] retain];

	return self;
}

- (void)dealloc
{
	[_pushr release];
	[_settings release];
	[super dealloc];
}

#pragma mark UIAlertSheet delegation
- (void)alertSheet: (UIAlertSheet *)sheet buttonClicked: (int)button
{
	[sheet dismiss];

	switch (button) {
		case 1:
			[_pushr openURL: [self authURL]];
			break;
		default:
			[_pushr terminate];
			break;
	}
}

#pragma mark XML helper functions
- (BOOL)sanityCheck: (id)responseDocument error: (NSError *)err
{
	NSXMLNode *rsp = [[responseDocument children] objectAtIndex: 0];
	if (![[rsp name] isEqualToString: @"rsp"]) {
		NSLog(@"This is not an <rsp> tag! Bailing out.");
		return FALSE;
	}

	id element = [[NSClassFromString(@"NSXMLElement") alloc] initWithXMLString: [rsp XMLString] error: &err];
	if (![[[element attributeForName: @"stat"] stringValue] isEqualToString: @"ok"]) {
		NSLog(@"The status is not 'ok', and we have no error recovery.");
		NSLog(@"XML: %@", [rsp XMLString]);
		[element release];
		return FALSE;
	}

	[element release];
	return TRUE;
}

/*
 * Returns an array of XMLNode objects with name matching nodeName. [ken] get is unusual
 */
- (NSArray *)getXMLNodesNamed: (NSString *)nodeName fromResponse: (NSData *)responseData
{
	NSError *err = nil;
	id responseDoc = [[NSClassFromString(@"NSXMLDocument") alloc] initWithData: responseData options: 0 error: &err];
	if (![self sanityCheck: responseDoc error: err]) {
		NSLog(@"Flickr returned an error!");
		[_pushr popupFailureAlertSheet];
		[responseDoc release];
		return nil;
	}

	NSMutableArray *matchingNodes = [NSMutableArray array];
	NSArray *nodes = [responseDoc children];
	NSEnumerator *chain = [nodes objectEnumerator];
	NSXMLNode *node = nil;

	while ((node = [chain nextObject])) {
		if (![[node name] isEqualToString: nodeName]) {
			nodes = [[nodes lastObject] children];
			chain = [nodes objectEnumerator];
			continue;
		}

		[matchingNodes addObject: node];
	}

	[responseDoc release];

	return [NSArray arrayWithArray: matchingNodes];
}

/*
 * Returns a dictionary filled with the node names, node values, node attribute names, and attribute values. [ken] get is unusual
 */
- (NSDictionary *)getXMLNodesAndAttributesFromResponse: (NSData *)responseData
{
	NSError *err = nil;
	id responseDoc = [[NSClassFromString(@"NSXMLDocument") alloc] initWithData: responseData options: 0 error: &err];
	if (![self sanityCheck: responseDoc error: err]) {
		NSLog(@"Flickr returned an error!");
		[_pushr popupFailureAlertSheet];
		[responseDoc release];
		return nil;
	}

	NSMutableDictionary *nodesWithAttributes = [NSMutableDictionary dictionary];
	NSArray *nodes = [responseDoc children];
	NSEnumerator *chain = [nodes objectEnumerator];
	NSXMLNode *node = nil;

	while ((node = [chain nextObject])) {
		id element = [[NSClassFromString(@"NSXMLElement") alloc] initWithXMLString: [node XMLString] error: &err];
		if ([[element attributes] count] > 0) {
			NSEnumerator *attributeChain = [[element attributes] objectEnumerator];
			id attribute = nil;
			while ((attribute = [attributeChain nextObject]))
				[nodesWithAttributes setObject: [attribute stringValue] forKey: [NSString stringWithFormat: @"%@%@", [node name], [attribute name]]];
		}

		[nodesWithAttributes setObject: [node stringValue] forKey: [node name]];

		if ([[node children] count] > 0 && [[[[node children] objectAtIndex: 0] name] length] > 0) {
			nodes = [node children];
			chain = [nodes objectEnumerator];
		}

		[element release];
	}

	[responseDoc release];

	return [NSDictionary dictionaryWithDictionary: nodesWithAttributes]; // [ken] we'd usually just return the mutable dict
}

#pragma mark internal functions
/*
 * Returns a URL with the parameters and values properly appended, including the call signing that Flickr requires from our app.
 *
 * This method made possible by extending system classes (without having to inherit from them.) Hooray!
 */
- (NSURL *)signedURL: (NSDictionary *)parameters withBase: (NSString *)base
{
	NSMutableString *url = [NSMutableString stringWithFormat: @"%@?", base];
	NSMutableString *sig = [NSMutableString stringWithString: PUSHR_SHARED_SECRET];

	[sig appendString: [[parameters pairsJoinedByString: @""] componentsJoinedByString: @""]];
	[url appendString: [[parameters pairsJoinedByString: @"="] componentsJoinedByString: @"&"]];
	[url appendString: [NSString stringWithFormat: @"&api_sig=%@", [sig md5HexHash]]];

	return [NSURL URLWithString: url];
}

/*
 * By default, we want the FLICKR_REST_URL as the base for our calls.
 */
- (NSURL *)signedURL: (NSDictionary *)parameters
{
	return [self signedURL: parameters withBase: FLICKR_REST_URL];
}

/*
 * Returns a one-time-use authorization URL; this URL is a page where the user can tell Flickr to give us permission to upload pictures to their account.
 */
- (NSURL *)authURL
{
	NSArray *keys = [NSArray arrayWithObjects: @"api_key", @"perms", @"frob", nil];
	NSArray *vals = [NSArray arrayWithObjects: PUSHR_API_KEY, FLICKR_WRITE_PERMS, [self frob], nil];
	NSDictionary *params = [NSDictionary dictionaryWithObjects: vals forKeys: keys];

	return [self signedURL: params withBase: FLICKR_AUTH_URL];
}

/*
 * Get a frob from Flickr, to put in the URL that we send the user to to get their permission to upload pics.
 */
- (NSString *)frob
{
	NSArray *keys = [NSArray arrayWithObjects: @"api_key", @"method", nil];
	NSArray *vals = [NSArray arrayWithObjects: PUSHR_API_KEY, FLICKR_GET_FROB, nil];
	NSDictionary *params = [NSDictionary dictionaryWithObjects: vals forKeys: keys];

	NSURL *url = [self signedURL: params];
	NSData *responseData = [NSData dataWithContentsOfURL: url];

	NSString *_frob = [[[self getXMLNodesNamed: @"frob" fromResponse: responseData] lastObject] stringValue];

	[_settings setObject: _frob forKey: @"frob"];
	[_settings synchronize];

	return [NSString stringWithString: _frob];
}

#pragma mark externally-visible interface
/*
 * Get the tags the user has already set on their photos. 
 * TODO: At some point, we should offer a UI to let them tag their future photos with the same tags.
 */
- (NSArray *)tags
{
	NSArray *keys = [NSArray arrayWithObjects: @"api_key", @"method", @"user_id", nil];
	NSArray *vals = [NSArray arrayWithObjects: PUSHR_API_KEY, FLICKR_GET_TAGS, [_settings stringForKey: @"nsid"], nil];
	NSDictionary *params = [NSDictionary dictionaryWithObjects: vals forKeys: keys];

	NSURL *url = [self signedURL: params];
	NSData *responseData = [NSData dataWithContentsOfURL: url];
	NSMutableArray *_tags = [NSMutableArray array];

	NSEnumerator *iterator = [[self getXMLNodesNamed: @"tag" fromResponse: responseData] objectEnumerator];
	id currentTagNode = nil;
	while ((currentTagNode = [iterator nextObject]))
		[_tags addObject: [currentTagNode stringValue]];

	return [NSArray arrayWithArray: _tags];
}

/*
 * Pop up a dialog so the user can tell Flickr it's cool for us to push pictures to their account.
 */
- (void)sendToGrantPermission
{
	UIAlertSheet *alertSheet = [[[UIAlertSheet alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 320.0f, 240.0f)] autorelease];
	[alertSheet setTitle: @"Can't upload to Flickr"];
	[alertSheet setBodyText: @"Pushr needs your permission to upload pictures to Flickr."];
	[alertSheet addButtonWithTitle: @"Proceed"];
	[alertSheet addButtonWithTitle: @"Cancel"];
	[alertSheet setDelegate: self];
	[alertSheet setRunsModal: YES];
	[alertSheet popupAlertAnimated: YES];
	[_settings setBool: TRUE forKey: @"sentToGetToken"];
}

/*
 * We have a frob that Flickr generated, and we used it in the URL we sent the user to (so that they could give us permission to upload pictures to their account). Now, we assume the user clicked on the 'Okay!' button the page we sent them to go click, and our frob can now be traded for a token.
 */
- (void)tradeFrobForToken
{
	NSArray *keys = [NSArray arrayWithObjects: @"api_key", @"method", @"frob", nil];
	NSArray *vals = [NSArray arrayWithObjects: PUSHR_API_KEY, FLICKR_GET_TOKEN, [_settings stringForKey: @"frob"], nil];
	NSDictionary *params = [NSDictionary dictionaryWithObjects: vals forKeys: keys];

	NSData *responseData = [NSData dataWithContentsOfURL: [self signedURL: params]];

	NSDictionary *tokenDictionary = [self getXMLNodesAndAttributesFromResponse: responseData];
	NSArray *responseKeys = [tokenDictionary allKeys];
	if (!([responseKeys containsObject: @"token"] && [responseKeys containsObject: @"usernsid"] && [responseKeys containsObject: @"userusername"])) {
		NSLog(@"Flickr returned an error!");
		[_settings removeObjectForKey: @"frob"];
		[_settings synchronize];
		[self sendToGrantPermission];
		return;
	}

	[_settings setObject: [tokenDictionary objectForKey: @"token"] forKey: @"token"];
	[_settings setObject: [tokenDictionary objectForKey: @"usernsid"] forKey: @"nsid"];
	[_settings setObject: [tokenDictionary objectForKey: @"userusername"] forKey: @"username"];
	[_settings removeObjectForKey: @"frob"];
	[_settings synchronize];
}

/*
 * We have a token, but is it valid? Maybe the user decided to de-authorize us and we can't push photos to their account anymore. This is how we make sure our token is valid.
 */
- (void)checkToken
{
	NSArray *keys = [NSArray arrayWithObjects: @"api_key", @"auth_token", @"method", nil];
	NSArray *vals = [NSArray arrayWithObjects: PUSHR_API_KEY, [_settings stringForKey: @"token"], FLICKR_CHECK_TOKEN, nil];
	NSDictionary *params = [NSDictionary dictionaryWithObjects: vals forKeys: keys];
	NSData *responseData = [NSData dataWithContentsOfURL: [self signedURL: params]];
	NSDictionary *tokenDictionary = [self getXMLNodesAndAttributesFromResponse: responseData];
	NSArray *responseKeys = [tokenDictionary allKeys];
	if (!([responseKeys containsObject: @"token"] && [responseKeys containsObject: @"usernsid"] && [responseKeys containsObject: @"userusername"])) {
		NSLog(@"Failed the sanity check when verifying our token. Bailing!");
		[_settings setBool: FALSE forKey: @"sentToGetToken"];
		[self sendToGrantPermission];
		return;
	}

	NSLog(@"Well, our token seems good.");
}

/*
 * Takes a JPG file at the specified filesystem path, and uploads it to Flickr using CFNetwork, because there is no way of getting the number of bytes written from an HTTP POST request using the NSHTTP API.
 *
 * This is, without a doubt, the ugliest code in the entire application.
 */
- (NSString *)pushPhoto: (NSString *)pathToJPG
{
	NSString *token = [_settings stringForKey: @"token"];
	NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys: PUSHR_API_KEY, @"api_key", token, @"auth_token", nil];
	if ([[ExtendedAttributes allKeysAtPath: pathToJPG] containsObject: NAME_ATTRIBUTE])
		[params setObject: [ExtendedAttributes stringForKey: NAME_ATTRIBUTE atPath: pathToJPG] forKey: @"title"];
	if ([[ExtendedAttributes allKeysAtPath: pathToJPG] containsObject: DESCRIPTION_ATTRIBUTE])
		[params setObject: [ExtendedAttributes stringForKey: DESCRIPTION_ATTRIBUTE atPath: pathToJPG] forKey: @"description"];
	if ([[_settings arrayForKey: @"defaultTags"] count] > 0)
		[params setObject: [[_settings arrayForKey: @"defaultTags"] componentsJoinedByString: @" "] forKey: @"tags"];
	if ([[ExtendedAttributes allKeysAtPath: pathToJPG] containsObject: TAGS_ATTRIBUTE])
		[params setObject: [[ExtendedAttributes objectForKey: TAGS_ATTRIBUTE atPath: pathToJPG] componentsJoinedByString: @" "] forKey: @"tags"];
	if ([[_settings arrayForKey: @"defaultPrivacy"] count] > 0 || [[ExtendedAttributes allKeysAtPath: pathToJPG] containsObject: PRIVACY_ATTRIBUTE]) {
		NSArray *privacy = [_settings arrayForKey: @"defaultPrivacy"];
		if ([[ExtendedAttributes allKeysAtPath: pathToJPG] containsObject: PRIVACY_ATTRIBUTE])
			privacy = [ExtendedAttributes objectForKey: PRIVACY_ATTRIBUTE atPath: pathToJPG];

		if ([privacy containsObject: @"Public"]) {
			[params setObject: @"1" forKey: @"is_public"];
		} else {
			[params setObject: @"0" forKey: @"is_public"];
			if ([privacy containsObject: @"Friends"])
				[params setObject: @"1" forKey: @"is_friend"];
			if ([privacy containsObject: @"Family"])
				[params setObject: @"1" forKey: @"is_family"];
		}
	}
	NSArray *pairs = [params pairsJoinedByString: @""];
	NSString *api_sig = [NSString stringWithFormat: @"%@%@", PUSHR_SHARED_SECRET, [pairs componentsJoinedByString: @""]];
	[params setObject: [api_sig md5HexHash] forKey: @"api_sig"];
	NSData *jpgData = [NSData dataWithContentsOfFile: pathToJPG];
	[params setObject: jpgData forKey: @"photo"];

	NSMutableData *body = [[NSMutableData alloc] initWithLength: 0];
	[body appendData: [[[[NSString alloc] initWithFormat: @"--%@\r\n", @MIME_BOUNDARY] autorelease] dataUsingEncoding: NSUTF8StringEncoding]];

	NSEnumerator *enumerator = [params keyEnumerator];
	id key = nil;
	while ((key = [enumerator nextObject])) {
		id val = [params objectForKey: key];
		id keyHeader = nil;
		if ([key isEqualToString: @"photo"]) {
			// If this is the photo...
			keyHeader = [[NSString stringWithFormat: @"Content-Disposition: form-data; name=\"photo\"; filename=\"%@\"\r\nContent-Type: image/jpeg\r\n\r\n", pathToJPG] dataUsingEncoding: NSUTF8StringEncoding];
			[body appendData: keyHeader];
			[body appendData: val];
		} else {
			// Treat all other values as strings.
			keyHeader = [NSString stringWithFormat: @"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key];
			[body appendData: [keyHeader dataUsingEncoding: NSUTF8StringEncoding]];
			[body appendData: [val dataUsingEncoding: NSUTF8StringEncoding]];			
		}
		[body appendData: [[NSString stringWithFormat: @"\r\n--%@\r\n", @MIME_BOUNDARY] dataUsingEncoding: NSUTF8StringEncoding]];
	}

	[body appendData: [[NSString stringWithString: @"--\r\n"] dataUsingEncoding: NSUTF8StringEncoding]];

	CFURLRef _uploadURL = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)FLICKR_UPLOAD_URL, NULL);
	CFHTTPMessageRef _request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("POST"), _uploadURL, kCFHTTPVersion1_1);
	CFRelease(_uploadURL);
	_uploadURL = NULL;

	CFHTTPMessageSetHeaderFieldValue(_request, CFSTR("Content-Type"), CFSTR(CONTENT_TYPE));
	CFHTTPMessageSetHeaderFieldValue(_request, CFSTR("Host"), CFSTR("api.flickr.com"));
	CFHTTPMessageSetHeaderFieldValue(_request, CFSTR("Content-Length"), (CFStringRef)[NSString stringWithFormat: @"%d", [body length]]);
	CFHTTPMessageSetBody(_request, (CFDataRef)body);

	CFReadStreamRef _readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, _request);
	CFReadStreamOpen(_readStream);

	NSMutableString *responseString = [NSMutableString string];
	CFIndex numBytesRead;
	long bytesWritten, previousBytesWritten = 0;
	UInt8 buf[1024];
	BOOL doneUploading = NO;

	while (!doneUploading) {
		CFNumberRef cfSize = CFReadStreamCopyProperty(_readStream, kCFStreamPropertyHTTPRequestBytesWrittenCount);
		CFNumberGetValue(cfSize, kCFNumberLongType, &bytesWritten);
		CFRelease(cfSize);
		cfSize = NULL;

		if (bytesWritten > previousBytesWritten) {
			previousBytesWritten = bytesWritten;
			NSNumber *progress = [NSNumber numberWithFloat: ((float)bytesWritten / (float)[body length])];
			[_pushr performSelectorOnMainThread: @selector(updateProgress:)  withObject: progress waitUntilDone: YES];
		}

		if (!CFReadStreamHasBytesAvailable(_readStream)) {
			usleep(3600);
			continue;
		}

		numBytesRead = CFReadStreamRead(_readStream, buf, 1024);
		if (numBytesRead < 1024)
			buf[numBytesRead] = 0;			
		[responseString appendFormat: @"%s", buf];

		if (CFReadStreamGetStatus(_readStream) == kCFStreamStatusAtEnd) doneUploading = YES;
	}
	[body release];

	CFReadStreamClose(_readStream);
	CFRelease(_request);
	_request = NULL;
	CFRelease(_readStream);
	_readStream = NULL;

	return [NSString stringWithString: responseString];
}

/*
 * When the user clicks on the 'Push to Flickr' button, push the photos that haven't been pushed yet, and pass the XML for the responses back to the main class when finished.
 */
- (void)triggerUpload: (id)photos
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray *responses = [NSMutableArray array];

	NSEnumerator *enumerator = [photos objectEnumerator];
	id photo = nil;
	while ((photo = [enumerator nextObject])) {
		[_pushr performSelectorOnMainThread: @selector(startingToPush:) withObject: photo waitUntilDone: NO];
		[responses addObject: [self pushPhoto: photo]];
		[ExtendedAttributes setString: @"true" forKey: PUSHED_ATTRIBUTE atPath: photo];
		[_pushr performSelectorOnMainThread: @selector(donePushing:) withObject: photo waitUntilDone: NO];
	}

	[_pushr performSelectorOnMainThread: @selector(allDone:) withObject: responses waitUntilDone: YES];
	[pool release];
}

@end
