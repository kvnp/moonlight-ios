//
//  WakeOnLanManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "WakeOnLanManager.h"
#import "Utils.h"
#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <ifaddrs.h>

@implementation WakeOnLanManager

static const int numStaticPorts = 2;
static const int staticPorts[numStaticPorts] = {
    9, // Standard WOL port (privileged port)
    47009, // Port opened by Moonlight Internet Hosting Tool for WoL (non-privileged port)
};
static const int numDynamicPorts = 5;
static const int dynamicPorts[numDynamicPorts] = {
    47998, 47999, 48000, 48002, 48010, // Ports opened by GFE/Sunshine
};

+ (void) populateAddress:(struct sockaddr_storage*)addr withPort:(unsigned short)port {
    if (addr->ss_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in*)addr;
        sin->sin_port = htons(port);
    }
    else if (addr->ss_family == AF_INET6) {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6*)addr;
        sin6->sin6_port = htons(port);
    }
}

+ (void) wakeHost:(TemporaryHost*)host {
    NSData* wolPayload = [WakeOnLanManager createPayload:host];
    
    for (int i = 0; i < 6; i++) {
        NSString* address;
        struct addrinfo hints, *res, *curr;
        
        // try all ip addresses
        if (i == 0 && host.localAddress != nil) {
            address = host.localAddress;
            NSLog(@"localAddress in wakeHost: %@", host.localAddress);
        } else if (i == 1 && host.externalAddress != nil) {
            address = host.externalAddress;
            NSLog(@"externalAddress in wakeHost: %@", address);
        } else if (i == 2 && host.address != nil) {
            address = host.address;
            NSLog(@"Address in wakeHost: %@", address);
        } else if (i == 3 && host.ipv6Address != nil) {
            address = host.ipv6Address;
            NSLog(@"ipv6Address in wakeHost: %@", address);
        } else if (i == 4) {
            address = @"255.255.255.255";
        } else if (i == 5 && host.localAddress != nil) {
            address = host.localAddress;
        } else {
            // Requested address wasn't present
            continue;
        }
        
        // Get the raw address and base port from the address+port string
        NSString* rawAddress = [Utils addressPortStringToAddress:address];
        unsigned short basePort = [Utils addressPortStringToPort:address];
        
        // Loop 5 is for using the broadcast address
        if (i == 5) {
            NSString *subnetMask = [self getSubnetMask];
            if (subnetMask == nil) {
                subnetMask = @"255.255.255.0";
            }
            rawAddress = [self calculateBroadcastAddressForIP:rawAddress withSubnetMask:subnetMask];
        }
        NSLog(@"rawAddress in wakeHost: %@", rawAddress);

        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_flags = AI_ADDRCONFIG;
        if (getaddrinfo([rawAddress UTF8String], NULL, &hints, &res) != 0 || res == NULL) {
            // Failed to resolve address
            Log(LOG_E, @"Failed to resolve WOL address");
            continue;
        }
        
        // Try all addresses that this DNS name resolves to. We have
        // to create a new socket each time because the addresses
        // may be different address families.
        for (curr = res; curr != NULL; curr = curr->ai_next) {
            int wolSocket;
            int val;
            
            wolSocket = socket(curr->ai_family, SOCK_DGRAM, IPPROTO_UDP);
            if (wolSocket < 0) {
                Log(LOG_E, @"Failed to create WOL socket");
                continue;
            }
            
            val = 1;
            setsockopt(wolSocket, SOL_SOCKET, SO_BROADCAST, &val, sizeof(val));
            
            struct sockaddr_storage addr;
            memset(&addr, 0, sizeof(addr));
            memcpy(&addr, curr->ai_addr, curr->ai_addrlen);
            
            for (int j = 0; j < numStaticPorts; j++) {
                [WakeOnLanManager populateAddress:&addr withPort:staticPorts[j]];
                long err = sendto(wolSocket,
                                 [wolPayload bytes],
                                 [wolPayload length],
                                 0,
                                 (struct sockaddr*)&addr,
                                 curr->ai_addrlen);
                Log(LOG_I, @"Sending WOL packet to port %u returned: %ld", staticPorts[j], err);
            }
            
            for (int j = 0; j < numDynamicPorts; j++) {
                // Offset the WoL dynamic ports by the base port
                unsigned short port = ((int)dynamicPorts[j] - 47989) + basePort;
                
                [WakeOnLanManager populateAddress:&addr withPort:port];
                long err = sendto(wolSocket,
                                 [wolPayload bytes],
                                 [wolPayload length],
                                 0,
                                 (struct sockaddr*)&addr,
                                 curr->ai_addrlen);
                Log(LOG_I, @"Sending WOL packet to port %u returned: %ld", port, err);
            }
            
            close(wolSocket);
        }
        freeaddrinfo(res);
    }
}

+ (NSData*) createPayload:(TemporaryHost*)host {
    NSMutableData* payload = [[NSMutableData alloc] initWithCapacity:102];
    
    // 6 bytes of FF
    UInt8 header = 0xFF;
    for (int i = 0; i < 6; i++) {
        [payload appendBytes:&header length:1];
    }
    
    // 16 repitiions of MAC address
    NSData* macAddress = [self macStringToBytes:host.mac];
    for (int j = 0; j < 16; j++) {
        [payload appendData:macAddress];
    }
    
    return payload;
}

+ (NSData*) macStringToBytes:(NSString*)mac {
    NSString* macString = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
    Log(LOG_D, @"MAC: %@", macString);
    return [Utils hexToBytes:macString];
}


+ (NSString *)calculateBroadcastAddressForIP:(NSString *)ipAddress withSubnetMask:(NSString *)subnetMask {
    struct in_addr ip;
    struct in_addr mask;
    struct in_addr broadcast;
    
    if (inet_pton(AF_INET, [ipAddress UTF8String], &ip) != 1) {
        NSLog(@"Invalid IP address format");
        return nil;
    }
    
    if (inet_pton(AF_INET, [subnetMask UTF8String], &mask) != 1) {
        NSLog(@"Invalid subnet mask format");
        return nil;
    }
    
    broadcast.s_addr = ip.s_addr | ~mask.s_addr;
    
    char broadcastAddress[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &broadcast, broadcastAddress, INET_ADDRSTRLEN) == NULL) {
        NSLog(@"Failed to convert broadcast address to string");
        return nil;
    }
    
    return [NSString stringWithUTF8String:broadcastAddress];
}

+ (NSString *)getSubnetMask {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSString *subnetMask = nil;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    subnetMask = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_netmask)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return subnetMask;
}
@end
