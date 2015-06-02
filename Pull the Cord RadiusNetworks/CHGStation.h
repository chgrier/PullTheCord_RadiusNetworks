//
//  CHGStation.h
//  Pull the Cord RadiusNetworks
//
//  Created by Charles Grier on 2/20/15.
//  Copyright (c) 2015 Grier Mobile Development. All rights reserved.
//

#import <Foundation/Foundation.h>
@import CoreLocation;

@interface CHGStation : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *title;  // conforms to MKAnnotaion protocol
@property (nonatomic, copy) NSString *subtitle; // conforms to MKAnnotation protocol
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSDictionary *attributes;
@property (nonatomic, copy) NSString *line;
@property (nonatomic, assign) NSString *stationNumber;
@property (nonatomic, assign) NSString *stationNumberAsString;

@property (nonatomic, assign) CLLocation *coords;

@property (nonatomic, assign) float latitude;
@property (nonatomic, assign) float longitude;
@property (nonatomic, assign) float radius;

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;

@end
