# DataFusionX Enterprise Legal Notice

DataFusionX Enterprise is commercial software distributed under a customer-specific license agreement. The deployment package is intended only for the licensed customer environment and delivery batch identified by the signed release manifest.

## Usage Boundary

- The package may be used only with a valid DataFusionX Enterprise commercial License.
- The package must not be redistributed, republished, reverse engineered, decompiled, or used to reconstruct DataFusionX Enterprise source code except where applicable law explicitly permits.
- The package does not include source code, private signing keys, customer activation credentials, or customer-specific License files.
- Public release artifacts are deployment entrypoints only. Customer identity, entitlement, activation code, and deployment fingerprint are controlled by License-Server-Center.

## Customer Responsibilities

- Keep `.env`, License files, activation codes, deployment fingerprints, tokens, private keys, and database credentials out of public tickets, public repositories, chat groups, and diagnostic bundles.
- Use fixed image tags and signed release manifests when deploying or upgrading.
- Back up the metadata PostgreSQL database and License volume before upgrade or rollback.
- Confirm that DataFusionX Enterprise is used as a control plane only. External Kafka topics, CDC connectors, Flink clusters, StarRocks tables, and relational target tables remain customer-managed resources.

## Support Materials

The package includes operational scripts and examples for deployment convenience. These materials do not expand the licensed usage scope and do not replace the signed commercial agreement.
