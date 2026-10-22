
import json
import os
import boto3  # pyright: ignore[reportMissingImports]

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["QUEUE_URL"]


def lambda_handler(event, context):
    try:
        # API Gateway sends the request body as a JSON string.
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid JSON"})
        }

    employee = {
        "employee_id": str(body.get("employee_id", "101")),
        "employee_name": str(body.get("employee_name", "Alice")),
        "checked_by": str(body.get("checked_by", "DemoUser"))
    }

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(employee)
    )

    return {
        "statusCode": 202,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Employee check request queued",
            "employee": employee
        })
    }
