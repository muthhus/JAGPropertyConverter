//
//  JAGPropertyConverter.m
//  JAGPropertyConverter
//
//  Created by James Gill on 2/13/12.
//
// Copyright (c) 2012 James A. Gill
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "JAGPropertyConverter.h"
#import "JAGPropertyFinder.h"
#import "JAGProperty.h"

@interface JAGPropertyConverter () 

- (id) convertCollection: (id) collection withTargetClass: (Class) targetClass;

/**
 * This converts a property to a PropertyModel-friendly form.
 * Dictionaries that can be detected as a PropertyModel subclass
 * are converted to that subclass and returned.
 * Other collections of objects are turned as those same collections,
 * but with their elements/values converted recursively.
 * Other objects, if they match the target class, are returned
 * unmodified, while "Base" PropertyList objects 
 * (NSNull, NSString, NSNumber, NSDate, NSData, and NSValue) are
 * returned either unmodified, or if there is a 'convertable'
 * targetClass, converted to that.
 */
- (id) convertPropertyToObject: (id) prop withTargetClass: (Class) targetClass;

@end

@implementation JAGPropertyConverter


@synthesize outputType = _outputType;
@synthesize identifyDict = _identifyDict;
@synthesize shouldConvert = _shouldConvert;
@synthesize shouldConvertClass = _shouldConvertClass;
@synthesize convertToDate = _convertToDate;
@synthesize convertFromDate = _convertFromDate;

#pragma mark - Lifecycle

+ (JAGPropertyConverter *) converterWithOutputType: (JAGOutputType) outputType {
    return [[JAGPropertyConverter alloc] initWithOutputType:outputType];
}

- (id) initWithOutputType: (JAGOutputType) outputType {
    self = [super init];
    if (self) {
        self.outputType = outputType;
        self.identifyDict = nil;
        self.convertToDate = nil;
        self.convertFromDate = nil;
        self.shouldConvert = ^(id obj) {return NO;};
        self.shouldConvertClass = ^(Class aClass) {return NO;};
    }
    return self;
}

- (id) init {
    return [self initWithOutputType:kJAGFullOutput];
}

#pragma mark - Convert To Dictionary

- (id) convertObjectToProperties: (id) object {
    if (!object) {
        return nil;
    } else if ([object isKindOfClass: [NSNull class]]
               || [object isKindOfClass: [NSString class]]) {
        //These objects are fine for all output types
        return object;    
    } else if ([object isKindOfClass: [NSNumber class]]) {
        if ( self.outputType == kJAGJSONOutput ) {
            if ( isfinite([object doubleValue]) ) {
                return object;
            } else {
                //JSON cannot handle +-infinity or NaN
                return nil;
            }
        } else {
            return object;
        }
    } else if ([object isKindOfClass: [NSDate class]]) {
        if ( self.outputType == kJAGFullOutput
            || self.outputType == kJAGPropertyListOutput ) {
            return object;
        } else if (self.convertFromDate) {
            return self.convertFromDate(object);
        } else {
            //Object is not safe for JSON.  Removing.
            return nil;
        }
        
    } else if ([object isKindOfClass: [NSData class]]) {
        //These objects are fine for PropertyLists, but not JSON
        if ( self.outputType == kJAGFullOutput
            || self.outputType == kJAGPropertyListOutput ) {
            return object;
        } else {
            //Object is not safe for JSON.  Removing.
            return nil;
        }
    } else if ( [object isKindOfClass: [NSValue class]] ) {
        //These objects are only ok for FullOutput
        if ( self.outputType == kJAGFullOutput ) {
            return object;
        } else {
            //Object is not safe for JSON or PropertyLists.  Removing.
            return nil;
        }
    } else if ( [object isKindOfClass: [NSURL class]] ) {
        //These objects are only ok for FullOutput
        if ( self.outputType == kJAGFullOutput ) {
            return object;
        } else {
            //Convert them to strings.
            return [object absoluteString];
        }
        
    } else if ([object isKindOfClass: [NSArray class]]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id obj in object) {
            id value = [self convertObjectToProperties:obj];
            if (value) {
                [array addObject: value];
            } else {
                NSLog(@"Object %@ can't be converted to properties.", obj);
            }
        }
        return array;
    } else if ([object isKindOfClass: [NSSet class]]) {
        id collection;
        if (self.outputType == kJAGJSONOutput) {
            //JSON only supports arrays.
            collection = [NSMutableArray array];
        } else {
            collection = [NSMutableSet set];
        }
        for (id obj in object) {
            id value = [self convertObjectToProperties:obj];
            if (value) {
                [collection addObject: value];
            } else {
                NSLog(@"Object %@ can't be converted to properties.", obj);
            }
        }
        return collection;
    } else if ([object isKindOfClass: [NSDictionary class]]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        for (id key in object) {
            if ( self.outputType == kJAGJSONOutput && ![key isKindOfClass:[NSString class]] ) {
                NSLog(@"JSON dictionaries must have string keys, skipping key %@", key);
                continue;
            }
            id value = [self convertObjectToProperties:[object objectForKey: key]];
            if (value) {
                [dict setObject: [self convertObjectToProperties: value] forKey: key];
            } else {
                NSLog(@"Unable to convert %@ to properties.", [object objectForKey: key]);
            }
        }
        return dict;
    } else if (self.shouldConvert(object)) {
        return [self convertToDictionary:object];
    } else {
        if ( self.outputType == kJAGFullOutput ) {
            return object;
        } else {
            NSLog(@"Object %@ is not safe for JSON or PropertyLists.  Removing.", [object class]);
            return nil;
        }
    }
    
}

- (NSDictionary*) convertToDictionary: (id) model {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSArray* properties = [JAGPropertyFinder propertiesForClass:[model class]];
    NSString* propertyName;
    for (JAGProperty *property in properties) {
        propertyName = [property name];
        SEL getter = [property getter];
        if (![model respondsToSelector:getter]) {
            //Found property without a valid getter. Skipping.
            continue;
        }
        //TODO: Should use the getter for this?  Harder to handle non-objects.
        id object = [model valueForKey:propertyName];
        [values setValue:[self convertObjectToProperties: object] forKey:propertyName];
    }
    return values;
}


#pragma mark - Convert From Dictionary

- (id) convertCollection: (id) collection withTargetClass: (Class) targetClass {
    if (!targetClass) {
        targetClass = [collection class];
    }
    id mutableCollection;
    //FIXME: If targetClass is a proper subclass, the property may not be settable to mutableCollection.
    if ([targetClass isSubclassOfClass:[NSArray class]]) {
        mutableCollection = [[NSMutableArray alloc] init];
    } else if ([targetClass isSubclassOfClass:[NSSet class]]) {
        mutableCollection = [[NSMutableSet alloc] init];
    } else {
        //TODO: Catch mutisets and the like.
        NSLog(@"Unable to convert %@ to collection type %@", [collection class], targetClass);
        return nil;
    }
    for (id elt in collection) {
        id value = [self convertPropertyToObject:elt];
        if (value) {
            [mutableCollection addObject: value];
        } else {
            NSLog(@"Object %@ can't be converted to properties.", [elt class]);
        }
    }
    return mutableCollection;
}

- (id) convertPropertyToObject: (id) prop {
    return [self convertPropertyToObject:prop withTargetClass: nil];
}

- (id) convertPropertyToObject: (id) prop withTargetClass: (Class) targetClass {
    if (!prop) {
        return nil;
    } else if ([prop isKindOfClass: [NSArray class]]
               || [prop isKindOfClass: [NSSet class]]) {
        return [self convertCollection:prop withTargetClass:targetClass];
    } else if ([prop isKindOfClass: [NSDictionary class]]) {
        //Is this a PropertyModel in disguise?
        Class modelClass = nil;
        if (self.identifyDict) {
            modelClass = self.identifyDict(prop);
        }
        if (modelClass) {
            id model = [[modelClass alloc] init];
            [self setPropertiesOf:model fromDictionary:prop];
            return model;
        } else if (targetClass && self.shouldConvertClass(targetClass)) {
            //Try to convert it to targetClass.
            id model = [[targetClass alloc] init];
            [self setPropertiesOf:model fromDictionary:prop];
            return model;
        } else {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            for (id key in prop) {
                [dict setValue: [self convertPropertyToObject: [prop valueForKey: key]]
                        forKey: key];
            }
            return dict;
        }
    } else if (targetClass && [prop isKindOfClass: targetClass]) {
        //If there are other collections that aren't subclases of NSSet, NSArray, or NSDictionary,
        //this won't convert their elements/values.
        return prop;
    } else if (targetClass 
               && [targetClass isSubclassOfClass:[NSDate class]] 
               && self.convertToDate) {
        //        NSLog(@"Found prop %@ for NSDate targetClass.  Converting.", prop);
        return self.convertToDate(prop);
    } else if ( targetClass 
               && [targetClass isSubclassOfClass:[NSURL class]]
               && [prop isKindOfClass:[NSString class]]
               )
    {        
        return [NSURL URLWithString:prop];
    } else if ([prop  isKindOfClass: [NSNull class]]
               || [prop isKindOfClass: [NSString class]]
               || [prop isKindOfClass: [NSNumber class]]
               || [prop isKindOfClass: [NSDate class]]
               || [prop isKindOfClass: [NSData class]]
               || [prop isKindOfClass: [NSValue class]]
               ) {
        return prop;
    }
    
    //TODO: Don't know what to do with this!  If we are using fullOutputType, we might be
    //getting other NSObject types, which we should be able to handle.
    NSLog(@"Unable to convert value %@ to an object property, returning nil.", [prop class]);
    return nil;
    
}

- (void) setPropertiesOf: (id) object fromDictionary: (NSDictionary*) dictionary {
    NSArray *propertyNames = [JAGPropertyFinder propertyNamesForClass: [object class]];
    JAGProperty *property;
    for (NSString *key in dictionary) {
        if ([propertyNames containsObject:key]) {
            property = [JAGPropertyFinder propertyForName: key inClass:[object class] ];
            if ([property isReadOnly]) continue;
            id value = [dictionary valueForKey:key];
            if ([property isObject]) {
                Class propertyClass = [property propertyClass];
                value = [self convertPropertyToObject: value withTargetClass:propertyClass];
            }
            [object setValue:value forKey:key];
        }
    }
}

@end
