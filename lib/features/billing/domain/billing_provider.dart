abstract class BillingProvider {
  Future<void> createSubscriptionSession({required String customerId});
  Future<void> cancelSubscription({required String subscriptionId});
}
