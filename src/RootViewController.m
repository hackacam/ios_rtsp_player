//
//  ViewController.m
//  rtsp_player
//
//  Created by J.C. Li on 11/15/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "RootViewController.h"
#import "FfmpegWrapper.h"
#import "YUVDisplayGLViewController.h"

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
- (IBAction)testYUVDisplay:(id)sender {
    
    // test GL view controller
    id yuvGLDisplay = [self.splitViewController.viewControllers lastObject];
    if ([yuvGLDisplay isKindOfClass:[YUVDisplayGLViewController class]]) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *referenceFramePath = [mainBundle pathForResource:@"testOutput720x480_yuv420_1" ofType:@"yuv"];
        NSData *testYUVInputData = [NSData dataWithContentsOfFile:referenceFramePath];
        
        NSMutableData *ydata = [NSData dataWithBytes:testYUVInputData.bytes length:720*480];
        NSMutableData *udata = [NSData dataWithBytes:(void *)((uint8_t*)(testYUVInputData.bytes)+ydata.length) length:720*480/4];
        NSMutableData *vdata = [NSData dataWithBytes:(void *)((uint8_t*)(testYUVInputData.bytes)+ydata.length+udata.length) length:720*480/4];
        AVFrameData *frame = [[AVFrameData alloc] init];
        frame.colorPlane0 = ydata;
        frame.colorPlane1 = udata;
        frame.colorPlane2 = vdata;
        frame.lineSize0 = [NSNumber numberWithInt:720];
        frame.lineSize1 = [NSNumber numberWithInt:360];
        frame.lineSize2 = [NSNumber numberWithInt:360];
        frame.width =[NSNumber numberWithInt:720];
        frame.height =[NSNumber numberWithInt:480];
        
        [yuvGLDisplay loadFrameData:frame];
    }
    
}

@end
