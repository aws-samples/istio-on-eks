# Module 2 - Traffic Management

This module shows the traffic routing capabilities of Istio service-mesh on Amazon EKS. The module is split into subdirectories for different traffic routing/shifting use cases.

0. [Add mesh resources to all the services](./00-add-mesh-resources/)
1. [Setup default route to v1](./01-default-route-v1/)
2. [Shift traffic to v2 based on weight](./02-shift-traffic-v2-weight/)
3. [Shift traffic to v2 based on path](./03-shift-traffic-v2-path/)
4. [Shift traffic to v2 based on header](./04-shift-traffic-v2-header/)

## Prerequisites:
- [Module 1 - Getting Started](../01-getting-started/)

Note: This module will build on the application resources deployed in 
[Module 1 - Getting Started](../01-getting-started/). That means you **don't** have to execute the [Destroy](../01-getting-started/README.md#destroy) section in Module 1.

## Destroy 

Refer to [Destroy](../01-getting-started/README.md#destroy) section for
cleanup of application resources.