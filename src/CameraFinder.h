//
//  CameraFinder.h
//  rtsp_player
//
//  Created by J.C. Li on 2/26/13.
//  Copyright (c) 2013 J.C. Li. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CameraFinderDelegate <NSObject>
@required
- (void) processCameraList: (NSArray *) cameraList;

@end

@interface CameraFinder : NSObject

@property (strong, nonatomic) id <CameraFinderDelegate> delegate;

- (void) startSearch;

@end
