import json
import os
import boto3  # type: ignore[import-not-found]

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):
    for record in event.get("Records", []):
        employee = json.loads(record["body"])

        employee_id = employee.get("employee_id", "unknown")
        employee_name = employee.get("employee_name", "unknown")
        checked_by = employee.get("checked_by", "unknown")

        message = (
            f"This employee detail is checked by user {checked_by}. "
            f"Employee ID: {employee_id}; "
            f"Employee name: {employee_name}."
        )

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="Employee Details Checked",
            Message=message
        )

    return {
        "statusCode": 200,
        "body": "Employee notification published"
    }
