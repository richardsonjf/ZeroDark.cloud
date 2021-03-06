/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <ZDCSyncableObjC/ZDCSyncableObjC.h>

#import "ZDCCloudDataInfo.h"
#import "ZDCNodeAnchor.h"
#import "ZDCShareList.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * ZDCNode encapsulates the metadata for a node.
 * This includes the basic information needed by the framework to sync the node with the cloud.
 *
 * @note Do NOT subclass ZDCNode.
 *       It's just for storing metadata.
 *       You're free to store your objects however you prefer.
 *
 * Every node in the treesystem can be thought of as 2 separate parts:
 *
 *
 * **Node Metadata**:
 *
 * The metadata is everything needed by the treesystem to store a node,
 * but excluding the actual content of the node. This includes information such as:
 *
 *  - what is the name of the node
 *  - who is the parent of this node
 *  - who was permission to read / write this node
 *  - when was the node last modified in the cloud
 *  - various sync related information, such as eTag(s)
 *  - various crypto information needed for encrypting & decrypting the content
 *
 * **Node Data**:
 *
 * The data is the actual content of the node. In other words, the content that your app generates.
 *
 * 
 * ZDCNode is responsible for the metadata.
 * And you're responsible for the data (using whatever objects, files, or formats you prefer).
 *
 *
 * During a pull, whenever ZeroDark discovers new nodes in the cloud,
 * it will automatically create ZDCNode instances and then inform the ZeroDarkCloudDelegate about them.
 *
 * When you want upload a new node to the cloud, a ZDCNode instance will be created and added to the treesystem.
 * You can do this the easy way, via `-[ZDCCloudTransaction createNodeWithPath:error:]`.
 * Or you can do it the manual way, via `-[ZDCCloudTransaction createNode:error:]`.
 * Either way, once the node is created, the framework will queue and perform the upload operation(s) for it.
 */
@interface ZDCNode : ZDCObject <NSCoding, NSCopying>

/**
 * Creates a new ZDCNode instance.
 *
 * Before the node can be used by the framework, you'll need to assign the `parentID` & `name` properties.
 */
- (instancetype)initWithLocalUserID:(NSString *)localUserID;

/**
 * Every ZDCNode has a uuid. This is commonly referred to as the nodeID:
 * > nodeID == ZDCNode.uuid
 *
 * The nodeID is only for referencing a ZDCNode instance in the LOCAL DATABASE.
 * NodeID's are NOT uploaded to the cloud, nor are they synced in any way.
 */
@property (nonatomic, readonly) NSString *uuid;

/**
 * A reference to the corresponding localUser. (localUserID == ZDCLocalUser.uuid)
 */
@property (nonatomic, readonly) NSString *localUserID;

/**
 * A reference to the parent ZDCNode.uuid.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *parentID;

/**
 * The cleartext name of the node.
 * For example: "Grandma's famous pumpkin bread.recipe".
 */
@property (nonatomic, copy, readwrite, nullable) NSString *name;

/**
 * The shareList encompasses the permissions for the node.
 */
@property (nonatomic, readonly) ZDCShareList *shareList;

/**
 * Node's can be assigned a "burn" date.
 * which tells the server to automatically delete the node at the specified time.
 *
 * This is especially useful when:
 * - you have temporary content that you want to cleanup from the cloud after a set time period
 * - you're sharing content with other users on a temporary basis
 *
 * @note The time at which the server deletes the content isn't exact.
 *       Currently the server performs this task as a batch operation every hour on the hour.
 */
@property (nonatomic, copy, readwrite, nullable) NSDate *burnDate;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Messaging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * For incoming messages (in the inbox), this value will be set to the userID that sent the message.
 */
@property (nonatomic, readonly, nullable) NSString *senderID;

/**
 * For outgoing messages & signals, this set contains the list of userID's for which the system
 * is still working on sending the node.
 */
@property (nonatomic, readonly, nullable) NSSet<NSString *> *pendingRecipients;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encryption Info
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The symmetric key that's used to encrypt & decrypt the node's data.
 * Every node uses a different (randomly generated) symmetric key.
 *
 * This property is created for you automatically.
 * For locally created nodes, the property is randomly generated.
 * For nodes that are pulled down from the server,
 * the encryption key is extracted & decrypted from the cloud data.
 */
@property (nonatomic, readonly) NSData *encryptionKey;

/**
 * Random bits used for creating cloudName's.
 * Every node has a different salt.
 *
 * A node's cloudName is generated by hashing the (cleartext) name,
 * along with the parent directory's dirSalt. Thus nodes with the
 * exact same name, but in different directories, will actually have
 * different names in the cloud.
 */
@property (nonatomic, readonly) NSData * dirSalt;

/**
 * This value represents the dirPrefix to be used by all the children.
 *
 * A file's cloudPath is: {treeID}/{dirPrefix_of_parent_node}/{cloudName}
 */
@property (nonatomic, readonly) NSString *dirPrefix;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud Info
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Every node has a server-assigned uuid, called the cloudID.
 * This value is immutable - once set by the server, it cannot be changed.
 *
 * The sync system uses the cloudID to detect when a node has been renamed or moved within the treesystem.
 * Since the server assigns this value, it is unknown until either:
 * - we've successfully uploaded the node's RCRD to the server at least once
 * - we've downloaded the node's RCRD from the server at least once
 */
@property (nonatomic, readonly, nullable) NSString *cloudID;

/**
 * The eTag value of the RCRD file in the cloud.
 * 
 * If this value is nil, then the node was created on this device,
 * and hasn't been updated yet.
 */
@property (nonatomic, readonly, nullable) NSString *eTag_rcrd;

/**
 * The eTag value of the data fork in the cloud.
 * 
 * If this value is nil, any of the following could be true:
 * - the node was created on this device, and hasn't been uploaded yet
 * - there isn't a data fork for this node (it's an empty node)
 * - the PullManager is in the process of updating, and hasn't discovered it yet
 */
@property (nonatomic, readonly, nullable) NSString *eTag_data;

/**
 * Returns the later of the 2 dates: lastModified_rcrd & lastModified_data
 */
@property (nonatomic, readonly, nullable) NSDate *lastModified;

/**
 * The date in which the RCRD file was last modified on the server.
 * This relates to the last time the node's treesystem information was changed, such as permissions.
 */
@property (nonatomic, readonly, nullable) NSDate *lastModified_rcrd;

/**
 * The date in which the DATA file was last modified on the server.
 * This relates to the last time the node's content was changed.
 */
@property (nonatomic, readonly, nullable) NSDate *lastModified_data;

/**
 * Stores the most recently downloaded information about the data file in the cloud.
 *
 * If you request any kind of download of the node via the DownloadManager,
 * this information gets automatically updated for you.
 *
 * @warning This information is not necessarily up-to-date.
 *          It's kept cached to allow you to inspect the previous data info before requesting a download.
 */
@property (nonatomic, readonly, nullable) ZDCCloudDataInfo *cloudDataInfo;

/**
 * Typically the cloudName is calculated by hashing node.name along with parentNode.dirSalt.
 * And thus there's no need to store the cloudName as it can be calcualted on-the-fly.
 *
 * @see `-[ZDCCloudPathManager cloudNameForNode:transaction:]`
 *
 * However, it's possible for a node to arrive in our tree with a hash mismatch.
 * That is, somebody didn't follow the hashing rules,
 * and the cloudName doesn't match what we'd expect via hashing.
 * If this occurs, we store the mismatched value here.
 */
@property (nonatomic, readonly, nullable) NSString *explicitCloudName;

/**
 * Pointers may point to nodes in a different treesystem.
 * These "foreign" nodes may be in a different user's treesystem (e.g. user's are collaborating).
 * Or they may be in the treesystem of a different treeID (e.g. an app upgrade transition).
 *
 * In any case, the "root" node for the grafting operation has an anchor
 * that points to the foreign location.
 *
 * @see `-[ZDCNodeManager anchorNodeForNode:transaction:]`
 */
@property (nonatomic, readonly, nullable) ZDCNodeAnchor *anchor;

/**
 * If the node is a pointer, specifies the ZDCNode.uuid that it points to.
 *
 * @see `-[ZDCNode isPointer]`
 */
@property (nonatomic, readonly, nullable) NSString * pointeeID;

/**
 * Convenience method: equivalent to (pointeeID != nil).
 */
@property (nonatomic, readonly) BOOL isPointer;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Random Values
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Generates a random 512 bit value (64 bytes).
 */
+ (NSData *)randomEncryptionKey;

/**
 * Generates a random 160 bit value (20 bytes).
 */
+ (NSData *)randomDirSalt;

/**
 * Generates a random string suitable for use as a dirPrefix.
 * These are 128 bits, encoded in hexadecimal as 32 characters.
 */
+ (NSString *)randomDirPrefix;

/**
 * Generates a random string suitable for use as a cloudName.
 * These are 160 bits, encoded in zBase32 as 32 characters.
 */
+ (NSString *)randomCloudName;

@end

NS_ASSUME_NONNULL_END
