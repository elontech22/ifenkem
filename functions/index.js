import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as functions from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// ----------------- Chat Notifications -----------------
export const sendChatNotification = functions.onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
        const msg = event.data;
        if (!msg) return null;

        const senderDoc = await db.collection("users").doc(msg.senderId).get();
        const senderName = senderDoc.exists ? senderDoc.data()?.name || "Someone" : "Someone";

        const receiverDoc = await db.collection("users").doc(msg.receiverId).get();
        const fcmToken = receiverDoc.exists ? receiverDoc.data()?.fcmToken : null;
        if (!fcmToken) return null;

        const payload = {
            notification: {
                title: `Message from ${senderName}`,
                body: msg.text || "New message",
            },
            data: {
                type: "chat_message",
                senderId: msg.senderId,
                senderName,
                message: msg.text || "",
            },
            token: fcmToken,
        };

        return messaging.send(payload);
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



// ----------------- Update Notifications -----------------
export const sendUpdateNotification = functions.onDocumentCreated(
    "updates/{updateId}",
    async (event) => {
        const update = event.data;
        if (!update) return null;

        const usersSnapshot = await db.collection("users").get();
        const tokens = usersSnapshot.docs
            .map((u) => u.data()?.fcmToken)
            .filter(Boolean);

        if (tokens.length === 0) return null;

        const payload = {
            notification: {
                title: "Update Available 🚀",
                body: update.message || "A new version is ready on Play Store!",
            },
            data: { type: "update_notification" },
        };

        return messaging.sendMulticast({ tokens, ...payload });
    }
);
