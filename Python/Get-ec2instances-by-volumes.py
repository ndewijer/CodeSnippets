import boto3
import json
from botocore.exceptions import ClientError
import logging

logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)


awsregion = "eu-west-1"

if __name__ == '__main__':

    try:
        # Connect AWS DynamoDB and SSM

        session = boto3.Session(profile_name='xxx')
        ec2 = session.resource('ec2', region_name=awsregion)
    except ClientError as err:
        logger.error(
            "Couldn't connect to DynamoDB or SSM. Here's why: %s: %s",
            err.response['Error']['Code'], err.response['Error']['Message'])
        raise

   # Get all ec2 volumes, find the name tag of the ec2 instance they are connected with and put it all in a dataframe
    volumes = ec2.volumes.all()
    df = []
    for volume in volumes:
        if volume.attachments:
            instance_id = volume.attachments[0]['InstanceId']
            instance = ec2.Instance(instance_id)
            for tag in instance.tags:
                if tag['Key'] == 'Name':
                    df.append([instance.id, tag['Value'], volume.id, volume.size, volume.state])
                    break


    # print the dataframe
    for row in df:
        print(row)
