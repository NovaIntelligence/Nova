import json, os, sys, time
from google.cloud import pubsub_v1

PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT") or "bamboo-autumn-474404-e7"
TOPIC   = "nova-approvals"

def main():
    if len(sys.argv) < 2:
        print("Usage: python approve_intent.py <intent_id>")
        sys.exit(2)
    intent_id = sys.argv[1]
    msg = {"intent_id": intent_id, "decision": "approve", "timestamp": int(time.time())}
    data = json.dumps(msg).encode("utf-8")
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT, TOPIC)
    future = publisher.publish(topic_path, data, content_type="application/json")
    print("Published:", msg)
    future.result(timeout=20)

if __name__ == "__main__":
    main()
