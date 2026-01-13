#!/usr/bin/env python3
"""
AWS Cost Estimator using AWS Pricing API
Parses Terraform plan JSON and estimates monthly costs
"""

import json
import sys
import boto3
from decimal import Decimal
from typing import Dict, List, Optional

class AWSCostEstimator:
    def __init__(self, region: str = 'eu-north-1'):
        self.region = region
        self.pricing_client = boto3.client('pricing', region_name='us-east-1')  # Pricing API only in us-east-1
        self.costs = {}

    def get_ec2_price(self, instance_type: str) -> Optional[Decimal]:
        """Get EC2 instance price per hour"""
        try:
            response = self.pricing_client.get_products(
                ServiceCode='AmazonEC2',
                Filters=[
                    {'Type': 'TERM_MATCH', 'Field': 'instanceType', 'Value': instance_type},
                    {'Type': 'TERM_MATCH', 'Field': 'location', 'Value': self._region_to_location()},
                    {'Type': 'TERM_MATCH', 'Field': 'operatingSystem', 'Value': 'Linux'},
                    {'Type': 'TERM_MATCH', 'Field': 'tenancy', 'Value': 'Shared'},
                    {'Type': 'TERM_MATCH', 'Field': 'capacitystatus', 'Value': 'Used'},
                    {'Type': 'TERM_MATCH', 'Field': 'preInstalledSw', 'Value': 'NA'},
                ],
                MaxResults=1
            )

            if response['PriceList']:
                price_item = json.loads(response['PriceList'][0])
                on_demand = price_item['terms']['OnDemand']
                price_dimensions = list(on_demand.values())[0]['priceDimensions']
                price_per_hour = list(price_dimensions.values())[0]['pricePerUnit']['USD']
                return Decimal(price_per_hour)
        except Exception as e:
            print(f"Warning: Could not get price for {instance_type}: {e}", file=sys.stderr)
        return None

    def get_rds_price(self, instance_class: str, engine: str = 'postgres') -> Optional[Decimal]:
        """Get RDS instance price per hour"""
        try:
            response = self.pricing_client.get_products(
                ServiceCode='AmazonRDS',
                Filters=[
                    {'Type': 'TERM_MATCH', 'Field': 'instanceType', 'Value': instance_class},
                    {'Type': 'TERM_MATCH', 'Field': 'location', 'Value': self._region_to_location()},
                    {'Type': 'TERM_MATCH', 'Field': 'databaseEngine', 'Value': 'PostgreSQL'},
                    {'Type': 'TERM_MATCH', 'Field': 'deploymentOption', 'Value': 'Single-AZ'},
                ],
                MaxResults=1
            )

            if response['PriceList']:
                price_item = json.loads(response['PriceList'][0])
                on_demand = price_item['terms']['OnDemand']
                price_dimensions = list(on_demand.values())[0]['priceDimensions']
                price_per_hour = list(price_dimensions.values())[0]['pricePerUnit']['USD']
                return Decimal(price_per_hour)
        except Exception as e:
            print(f"Warning: Could not get price for RDS {instance_class}: {e}", file=sys.stderr)
        return None

    def get_alb_price(self) -> Decimal:
        """Get ALB base price per hour (fixed)"""
        # ALB pricing: ~$0.0225 per hour + LCU charges
        # Using Stockholm (eu-north-1) pricing
        return Decimal('0.0225')

    def get_nat_gateway_price(self) -> Decimal:
        """Get NAT Gateway price per hour (fixed)"""
        # NAT Gateway pricing: ~$0.045 per hour in eu-north-1
        return Decimal('0.045')

    def _region_to_location(self) -> str:
        """Convert AWS region to Pricing API location name"""
        region_map = {
            'eu-north-1': 'EU (Stockholm)',
            'us-east-1': 'US East (N. Virginia)',
            'us-west-2': 'US West (Oregon)',
            'eu-west-1': 'EU (Ireland)',
        }
        return region_map.get(self.region, 'EU (Stockholm)')

    def parse_terraform_plan(self, plan_file: str) -> Dict:
        """Parse Terraform plan JSON and extract resources"""
        with open(plan_file, 'r') as f:
            plan = json.load(f)

        resources = {
            'ec2_instances': [],
            'rds_instances': [],
            'albs': 0,
            'nat_gateways': 0,
        }

        # Parse resource changes
        for change in plan.get('resource_changes', []):
            resource_type = change.get('type')
            change_action = change.get('change', {}).get('actions', [])

            # Skip destroy-only actions
            if change_action == ['delete']:
                continue

            after = change.get('change', {}).get('after', {})

            if resource_type == 'aws_instance':
                instance_type = after.get('instance_type')
                if instance_type:
                    resources['ec2_instances'].append(instance_type)

            elif resource_type == 'aws_launch_template':
                instance_type = after.get('instance_type')
                if instance_type:
                    resources['ec2_instances'].append(instance_type)

            elif resource_type == 'aws_db_instance':
                instance_class = after.get('instance_class')
                if instance_class:
                    resources['rds_instances'].append(instance_class)

            elif resource_type == 'aws_lb' or resource_type == 'aws_alb':
                resources['albs'] += 1

            elif resource_type == 'aws_nat_gateway':
                resources['nat_gateways'] += 1

        return resources

    def estimate_cost(self, plan_file: str) -> Dict:
        """Estimate monthly cost from Terraform plan"""
        resources = self.parse_terraform_plan(plan_file)

        monthly_cost = Decimal('0')
        breakdown = []

        # EC2 instances
        ec2_hourly = Decimal('0')
        for instance_type in resources['ec2_instances']:
            price = self.get_ec2_price(instance_type)
            if price:
                ec2_hourly += price
                breakdown.append(f"EC2 {instance_type}: ${price}/hour")

        if ec2_hourly > 0:
            ec2_monthly = ec2_hourly * 730  # 730 hours per month
            monthly_cost += ec2_monthly
            breakdown.append(f"**EC2 Total**: ${ec2_monthly:.2f}/month")

        # RDS instances
        rds_hourly = Decimal('0')
        for instance_class in resources['rds_instances']:
            price = self.get_rds_price(instance_class)
            if price:
                rds_hourly += price
                breakdown.append(f"RDS {instance_class}: ${price}/hour")

        if rds_hourly > 0:
            rds_monthly = rds_hourly * 730
            monthly_cost += rds_monthly
            breakdown.append(f"**RDS Total**: ${rds_monthly:.2f}/month")

        # ALB
        if resources['albs'] > 0:
            alb_price = self.get_alb_price()
            alb_monthly = alb_price * 730 * resources['albs']
            monthly_cost += alb_monthly
            breakdown.append(f"ALB ({resources['albs']}x): ${alb_monthly:.2f}/month (excluding LCU)")

        # NAT Gateway
        if resources['nat_gateways'] > 0:
            nat_price = self.get_nat_gateway_price()
            nat_monthly = nat_price * 730 * resources['nat_gateways']
            monthly_cost += nat_monthly
            breakdown.append(f"NAT Gateway ({resources['nat_gateways']}x): ${nat_monthly:.2f}/month (excluding data transfer)")

        return {
            'monthly_cost': float(monthly_cost),
            'breakdown': breakdown,
            'resources': resources
        }


def main():
    if len(sys.argv) < 2:
        print("Usage: aws-cost-estimate.py <terraform-plan.json>")
        sys.exit(1)

    plan_file = sys.argv[1]
    region = sys.argv[2] if len(sys.argv) > 2 else 'eu-north-1'

    estimator = AWSCostEstimator(region)
    result = estimator.estimate_cost(plan_file)

    # Output results
    print(f"\n## 💰 AWS Cost Estimation\n")
    print(f"**Estimated Monthly Cost**: ${result['monthly_cost']:.2f}\n")
    print("### Cost Breakdown\n")
    for item in result['breakdown']:
        print(f"- {item}")

    print("\n### Resources Detected\n")
    print(f"- EC2 Instances: {len(result['resources']['ec2_instances'])}")
    print(f"- RDS Instances: {len(result['resources']['rds_instances'])}")
    print(f"- Load Balancers: {result['resources']['albs']}")
    print(f"- NAT Gateways: {result['resources']['nat_gateways']}")

    print("\n**Note**: This is an estimate based on AWS Pricing API.")
    print("Actual costs may vary based on usage, data transfer, and other factors.\n")

    # Output JSON for GitHub Actions
    print("\n```json")
    print(json.dumps(result, indent=2))
    print("```")


if __name__ == '__main__':
    main()
