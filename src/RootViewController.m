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
#import "WebViewController.h"
#import "CameraFinder.h"
#import <QuartzCore/QuartzCore.h>
#include <arpa/inet.h>

@interface RootViewController () <UITextFieldDelegate, UISplitViewControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource, CameraFinderDelegate> {
    int _counter;
    BOOL searching;
}
@property (nonatomic, strong) FfmpegWrapper *h264dec;
@property (weak, nonatomic) IBOutlet UITextField *streamUrl;
@property (weak, nonatomic) IBOutlet UITextView *decodeStatusText;
@property (weak, nonatomic) IBOutlet UIPickerView *macAddressPickerView;


@property (strong, nonatomic) NSArray *ipcamList;
@property (strong, nonatomic) NSArray *channelList;
@property (strong, nonatomic) NSString *currentCameraIP;
@property (strong, nonatomic) NSString *currentCameraCh;

@property (strong, nonatomic) CameraFinder* cameraFinder;
@end

@implementation RootViewController
@synthesize h264dec=_h264dec;
@synthesize ipcamList = _ipcamList;
@synthesize channelList = _channelList;
@synthesize cameraFinder = _cameraFinder;
@synthesize currentCameraCh = _currentCameraCh;
@synthesize currentCameraIP = _currentCameraIP;

- (CameraFinder*) cameraFinder
{
    if (!_cameraFinder){
        _cameraFinder = [[CameraFinder alloc] init];
    }
    return _cameraFinder;
}

- (NSArray *) ipcamList
{
    if (!_ipcamList){
        _ipcamList = [[NSArray alloc] init];
    }
    return _ipcamList;
}

- (NSArray *) channelList
{
    if (!_channelList){
        _channelList = [[NSArray alloc] initWithObjects:@"CH01", @"CH02", @"CH03", @"CH04", nil];
    }
    return _channelList;
}

-(FfmpegWrapper *) h264dec
{
    if (!_h264dec){
        _h264dec = [[FfmpegWrapper alloc] init];
    }
    return _h264dec;
}

- (void) setH264dec:(FfmpegWrapper *)h264dec
{
    if (h264dec!=_h264dec){
        [_h264dec stopDecode];  // send the stop decode message to the decoder so it will not wait forever
        _h264dec = h264dec;
    }
}

- (void) updateCurrentUrl
{
    NSString *currentUrl = [NSString stringWithFormat:@"rtsp://%@:554/video/%@", self.currentCameraIP, self.currentCameraCh];
    self.streamUrl.text = currentUrl;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.streamUrl.delegate = self;
    self.decodeStatusText.editable = NO;
    self.decodeStatusText.layer.borderWidth = 5.0f;
    self.decodeStatusText.layer.borderColor = [[UIColor grayColor] CGColor];
    [self updateCurrentUrl];
        
    // set the split view controller delegate
    self.splitViewController.delegate = self;
    
    // set the delegate for the camera finder and start the search
    self.cameraFinder.delegate = self;
    [self.cameraFinder startSearch];
    
    
    // setup the pickerview delegate/datasource
    self.macAddressPickerView.delegate=self;
    self.macAddressPickerView.dataSource=self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)testYUVDisplay:(id)sender {
    
    // test GL view controller
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

    
    dispatch_queue_t testQueue = dispatch_queue_create("testQueue", NULL);
    dispatch_async(testQueue, ^{
        while (1) {
                
            
            id yuvGLDisplay = [self.splitViewController.viewControllers lastObject];
            if ([yuvGLDisplay isKindOfClass:[YUVDisplayGLViewController class]]) {
                
                [yuvGLDisplay loadFrameData:frame];
//                NSLog(@"loaded a frame");
//                usleep(20000);
            }
            }
    });

    
}

- (IBAction)setTestFileUrl:(id)sender
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *testH264FilePath = [mainBundle pathForResource:@"itur525_26kielharbour4_original_720x480_-avg-bps_2000000" ofType:@"h264"];
    self.streamUrl.text = testH264FilePath;
}

- (IBAction)startStreaming:(id)sender
{
    int status=0;
    self.h264dec=nil;
    status = [self.h264dec openUrl:self.streamUrl.text];
    id yuvGLDisplay = [self.splitViewController.viewControllers lastObject];
    if (![yuvGLDisplay isKindOfClass:[YUVDisplayGLViewController class]]){
        yuvGLDisplay = nil;
    }
        
    if (status==0){
        NSString *statusTxt = [NSString stringWithFormat:@"Connected to server: %@\n", self.streamUrl.text];
        self.decodeStatusText.text = [NSString stringWithFormat:@"%@%@", self.decodeStatusText.text, statusTxt];
        [self.h264dec startDecodingWithCallbackBlock:^(AVFrameData *frame) {
                [yuvGLDisplay loadFrameData:frame];
            if (_counter%60==0){
                NSLog(@"got %d frames", _counter);
            }
            _counter++;
        } waitForConsumer:YES completionCallback:^{
            NSLog(@"decode complete.");
        }];
    }else{
        NSString *statusTxt = [NSString stringWithFormat:@"failed to connect to server: %@\n", self.streamUrl.text];
        self.decodeStatusText.text = [NSString stringWithFormat:@"%@%@", self.decodeStatusText.text, statusTxt];
        self.h264dec=nil;
    }
    
}

- (IBAction)stopStreaming:(id)sender {
    [self.h264dec stopDecode];
    self.h264dec = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return NO;
}

-(void) textFieldDidBeginEditing:(UITextField *)textField
{
//    if (textField==self.configServerAddress){
//        [UIView beginAnimations:nil context:NULL];
//        [UIView setAnimationDelegate:self];
//        [UIView setAnimationDuration:0.5];
//        [UIView setAnimationBeginsFromCurrentState:YES];
//        textField.frame = CGRectMake(textField.frame.origin.x, (textField.frame.origin.y - 270.0), textField.frame.size.width, textField.frame.size.height);
//        [UIView commitAnimations];
//    }
}

-(void) textFieldDidEndEditing:(UITextField *)textField
{
//    if (textField==self.configServerAddress){
//        [UIView beginAnimations:nil context:NULL];
//        [UIView setAnimationDelegate:self];
//        [UIView setAnimationDuration:0.5];
//        [UIView setAnimationBeginsFromCurrentState:YES];
//        textField.frame = CGRectMake(textField.frame.origin.x, (textField.frame.origin.y + 270.0), textField.frame.size.width, textField.frame.size.height);
//        [UIView commitAnimations];
//    }
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"push to config webview"]){
        WebViewController *dstViewController = segue.destinationViewController;
//        dstViewController.configUrl = self.configServerAddress.text;
        NSString *address = [[self.streamUrl.text componentsSeparatedByString:@"/"] objectAtIndex:2];
        address = [[address componentsSeparatedByString:@":"] objectAtIndex:0];
        address = [NSString stringWithFormat:@"http://%@", address];
        dstViewController.configUrl = address;
    }
}

-(BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    id yuvGLDisplay = [self.splitViewController.viewControllers lastObject];
    if (![yuvGLDisplay isKindOfClass:[YUVDisplayGLViewController class]]){
        yuvGLDisplay = nil;
    }
    return [yuvGLDisplay shouldHideMaster];
}

-(void)splitViewController:(UISplitViewController *)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
}

-(void)splitViewController:(UISplitViewController *)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)pc
{
}

#pragma mark PickerView DataSource
-(CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component
{
    if (component==0){
        return pickerView.bounds.size.width*3/4;
    }else{
        return pickerView.bounds.size.width/4;
    }
}

- (NSInteger)numberOfComponentsInPickerView:
(UIPickerView *)pickerView
{
    return 2;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView
numberOfRowsInComponent:(NSInteger)component
{
    if (component==0){
        return self.ipcamList.count;
    }else{
        return self.channelList.count;
    }
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row
            forComponent:(NSInteger)component
{
    if (component==0){
        if (self.ipcamList.count){
            return [[self.ipcamList objectAtIndex:row] objectForKey:@"name"];
        }else{
            return @"";
        }
    }else{
        return [self.channelList objectAtIndex:row];
    }
}
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    if (component==0){
        NSString *cameraIP = [[self.ipcamList objectAtIndex:row] objectForKey:@"address"];
        self.currentCameraIP = [[NSString alloc] initWithString:cameraIP];
    }else{
        self.currentCameraCh = [NSString stringWithFormat:@"%d", row];
    }
    [self updateCurrentUrl];
}

#pragma mark CameraFinder delegate

-(void) processCameraList:(NSArray *)cameraList
{
    self.ipcamList = [[NSArray alloc] initWithArray:cameraList];
    [self.macAddressPickerView reloadAllComponents];
    if (!self.currentCameraIP){
        NSInteger currentCameraRow = [self.macAddressPickerView selectedRowInComponent:0];
        NSInteger currentChRow = [self.macAddressPickerView selectedRowInComponent:1];
        NSString *cameraIP = [[self.ipcamList objectAtIndex:currentCameraRow] objectForKey:@"address"];
        self.currentCameraIP = [[NSString alloc] initWithString:cameraIP];
        self.currentCameraCh = [NSString stringWithFormat:@"%d", currentChRow];
        [self updateCurrentUrl];
    }
}

@end
