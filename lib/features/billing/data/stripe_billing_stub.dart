import '../domain/billing_provider.dart';

class StripeBillingStub implements BillingProvider {
  @override
  Future<void> cancelSubscription({required String subscriptionId}) async {
    // Placeholder intencional: Stripe se habilita en la siguiente fase.
  }

  @override
  Future<void> createSubscriptionSession({required String customerId}) async {
    // Placeholder intencional: Stripe se habilita en la siguiente fase.
  }
}
