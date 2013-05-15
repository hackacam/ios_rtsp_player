//
//  CameraFinder.m
//  rtsp_player
//
//  Created by J.C. Li on 2/26/13.
//  Copyright (c) 2013 J.C. Li. All rights reserved.
//

#import "CameraFinder.h"
#include <arpa/inet.h>

@interface CameraFinder () <NSNetServiceDelegate, NSNetServiceBrowserDelegate>

// bonjour discovery
@property (strong, nonatomic) NSNetServiceBrowser *serviceBrowser;
@property (strong, nonatomic) NSMutableArray *services;
@property (strong, nonatomic) NSMutableArray *ipcamList;

@end

@implementation CameraFinder

@synthesize serviceBrowser = _serviceBrowser;
@synthesize services = _services;
@synthesize ipcamList = _ipcamList;

- (NSMutableArray *) ipcamList
{
    if (!_ipcamList){
        _ipcamList = [[NSMutableArray alloc] init];
    }
    return _ipcamList;
}

- (NSMutableArray *) services
{
    if (!_services){
        _services= [[NSMutableArray alloc] init];
    }
    return _services;
}

- (NSNetServiceBrowser *) serviceBrowser
{
    if (!_serviceBrowser){
        _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    }
    return _serviceBrowser;
}

- (void) startSearch
{
    [self.serviceBrowser setDelegate:self];
    [self.serviceBrowser searchForServicesOfType:@"_stretch-camera._tcp" inDomain:@""];
}

#pragma mark netServiceBrowser delegate

// Sent when browsing begins
- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
    NSLog(@"searching...");
}

// Sent when browsing stops
- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
    NSLog(@"stopped...");
}

// Sent if browsing fails
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict
{
    [self handleError:[errorDict objectForKey:NSNetServicesErrorCode]];
    NSLog(@"failed...");
}

- (void) printServices
{
    for (NSNetService *service in self.services){
        [service setDelegate:self];
        [service resolveWithTimeout:10];
    }
}
// Sent when a service appears
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    [self.services addObject:aNetService];
    if(!moreComing)
    {
        [self printServices];
    }
}

// Sent when a service disappears
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    [self.services removeObject:aNetService];
    if(!moreComing)
    {
    }
}

// Error handling code
- (void)handleError:(NSNumber *)error
{
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
    // Handle error here
}

#pragma mark netService delegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    for (NSData* data in [sender addresses]) {
        
        char addressBuffer[100];
        
        struct sockaddr_in* socketAddress = (struct sockaddr_in*) [data bytes];
        
        int sockFamily = socketAddress->sin_family;
        if (sockFamily == AF_INET || sockFamily == AF_INET6) {
            
            const char* addressStr = inet_ntop(sockFamily,
                                               &(socketAddress->sin_addr), addressBuffer,
                                               sizeof(addressBuffer));
            
            int port = ntohs(socketAddress->sin_port);
            
            if (addressStr && port){
                NSRange strechIPRange = [sender.name rangeOfString:@"stretch-ipcam-"];
                if (strechIPRange.location != NSNotFound){
                    //                    NSLog(@"Found service at %s:%d", addressStr, port);
                    NSString *addressNSstring = [[NSString alloc] initWithCString:addressStr encoding:NSUTF8StringEncoding];
                    NSString *macAddress = [sender.name substringFromIndex:(strechIPRange.location + strechIPRange.length)];
                    NSArray *itemObjs = [[NSArray alloc] initWithObjects:macAddress, addressNSstring, nil];
                    NSArray *itemKeys = [[NSArray alloc] initWithObjects:@"name", @"address", nil];
                    NSDictionary *item = [[NSDictionary alloc] initWithObjects:itemObjs forKeys:itemKeys];
                    
                    NSIndexSet *indexOfItem = [self.ipcamList indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                        if ([[obj objectForKey:@"name"] isEqualToString:macAddress]){
                            NSLog(@"found a duplicate.");
                            *stop=YES;
                            return YES;
                        }else{
                            return NO;
                        }
                    }];
                    if (indexOfItem.count==0){
                        [self.ipcamList addObject:item];
                        [self.delegate processCameraList:self.ipcamList];
                    }
                }
            }
        }
    }
}

@end
