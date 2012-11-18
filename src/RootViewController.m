//
//  ViewController.m
//  rtsp_player
//
//  Created by J.C. Li on 11/15/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "RootViewController.h"
#import "FfmpegWrapper.h"

@interface RootViewController (){
    int _counter;
}
@property (nonatomic, strong) FfmpegWrapper *h264dec;

@end

@implementation RootViewController
@synthesize h264dec=_h264dec;


-(FfmpegWrapper *) h264dec
{
    if (!_h264dec){
        _h264dec = [[FfmpegWrapper alloc] init];
    }
    return _h264dec;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
