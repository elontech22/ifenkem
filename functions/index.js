import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as functions from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();
const messaging = getMessaging();



// ----------------- Chat Notifications (fixed + logging) -----------------

export const sendChatNotification = functions.onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
        const msgSnap = event.data;
        if (!msgSnap.exists) {
            console.error("No message snapshot.");
            return null;
        }

        const msg = msgSnap.data(); // ✅ extract actual fields
        const messageId = msgSnap.id; // ✅ proper messageId

        const receiverId = msg.receiverId || msg.to || msg.toId;
        if (!receiverId) {
            console.error("Missing receiverId in message document.", messageId);
            return null;
        }

        const receiverDoc = await db.collection("users").doc(receiverId).get();
        if (!receiverDoc.exists) return null;

        const fcmToken = receiverDoc.data()?.fcmToken;
        if (!fcmToken || typeof fcmToken !== "string" || fcmToken.trim() === "") return null;

        const senderDoc = await db.collection("users").doc(msg.senderId).get();
        const senderName = senderDoc.exists ? senderDoc.data()?.name || "Someone" : "Someone";

        const messagePayload = {
            token: fcmToken,
            // notification: {
            //     title: `Message from ${senderName}`,
            //     body: msg.text || "New message",
            // },
            data: {
                type: "chat_message",
                title: `Message from ${senderName}`,
                body: msg.text || "New message",
                senderId: msg.senderId || "",
                senderName,
                message: msg.text || "",
                messageId, // ✅ pass messageId to frontend
            },
            android: {
                priority: "high",
                notification: { channelId: "chat_channel" },
            },
        };

        try {
            const resp = await messaging.send(messagePayload);
            console.log("Chat notification sent:", resp, "to token:", fcmToken);

            // ✅ update Firestore to mark as delivered
            await db
                .collection("chats")
                .doc(event.params.chatId)
                .collection("messages")
                .doc(messageId)
                .update({ delivered: true, messageId });

            return resp;
        } catch (err) {
            console.error("Failed to send chat notification:", err);
            return null; // ✅ avoid throwing unhandled errors
        }
    }
);




// ----------------- Like Notifications -----------------
export const sendLikeNotification = functions.onDocumentCreated(
    "likes/{targetUid}/received/{senderUid}",
    async (event) => {
        const targetUid = event.params.targetUid;
        const senderUid = event.params.senderUid;

        const likerDoc = await db.collection("users").doc(senderUid).get();
        const likerName = likerDoc.exists ? likerDoc.data()?.name || "Someone" : "Someone";

        const likedUserDoc = await db.collection("users").doc(targetUid).get();
        const fcmToken = likedUserDoc.exists ? likedUserDoc.data()?.fcmToken : null;
        if (!fcmToken) return null;

        const payload = {
            notification: {
                title: "New Like ❤️",
                body: `${likerName} liked your profile!`,
            },
            data: {
                type: "like_notification",
                likerId: senderUid,
                likerName,
            },

            token: fcmToken,
        };

        return messaging.send(payload);
    }
);

// ----------------- Update Notifications (fixed + logging) -----------------
export const sendUpdateNotification = functions.onDocumentCreated(
    "updates/{updateId}",
    async (event) => {
        const updateSnap = event.data;
        if (!updateSnap || !updateSnap.exists) {
            console.error("❌ No update snapshot found or update deleted.");
            return null;
        }

        const updateData = updateSnap.data();
        const updateId = updateSnap.id;

        const messageBody =
            updateData.message || "A new version of IfeNkem is ready on Play Store!";

        console.log("🚀 Update triggered:", updateId, messageBody);

        // ✅ Get all users with valid FCM tokens
        const usersSnapshot = await db.collection("users").get();
        const tokens = usersSnapshot.docs
            .map((u) => u.data()?.fcmToken)
            .filter((t) => typeof t === "string" && t.trim().length > 0);

        if (tokens.length === 0) {
            console.warn("⚠️ No valid FCM tokens found for update notification.");
            return null;
        }

        // ✅ Send each token individually for reliability (same pattern as chat)
        const results = [];
        for (const token of tokens) {
            const payload = {
                token,
                notification: {
                    title: "IfeNkem Update Available 🚀",
                    body: messageBody,
                },
                data: {
                    type: "update_notification",
                    title: "IfeNkem Update Available 🚀",
                    body: messageBody,
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "update_channel",
                        sound: "default",
                    },
                },
            };

            try {
                const resp = await messaging.send(payload);
                console.log("✅ Update notification sent:", resp, "to:", token);
                results.push(resp);
            } catch (err) {
                console.error("❌ Failed to send update to token:", token, err);
            }
        }

        // ✅ Update Firestore to mark the update delivery result
        try {
            await db.collection("updates").doc(updateId).update({
                deliveredCount: results.length,
                sentAt: new Date().toISOString(),
            });
        } catch (err) {
            console.error("⚠️ Could not update delivery status in Firestore:", err);
        }

        return results;
    }
);
