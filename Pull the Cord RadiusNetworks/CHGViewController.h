//
//  CHGViewController.h
//  Pull the Cord RadiusNetworks
//
//  Created by Charles Grier on 2/18/15.
//  Copyright (c) 2015 Grier Mobile Development. All rights reserved.
//

#import <UIKit/UIKit.h>

//# warning add your ProximityKit framework file to your target manually
@import ProximityKit;
@import MapKit;
@import AVFoundation;

@interface CHGViewController : UIViewController <RPKManagerDelegate, MKMapViewDelegate>

@property (strong, nonatomic) CLLocationManager *locationManager;

@end

