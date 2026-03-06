import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactService extends ChangeNotifier {
  /// Search for a contact by name (partial match).
  /// Returns a map with 'name' and 'phone' if found, or null.
  Future<Map<String, String>?> searchContact(String query) async {
    try {
      // Request permission if not already granted
      if (!await FlutterContacts.requestPermission()) {
        print("ContactService: Permission denied");
        return null;
      }

      // Fetch all contacts with phone numbers
      final contacts = await FlutterContacts.getContacts(withProperties: true);

      // Search for partial match (case-insensitive)
      final lowerQuery = query.toLowerCase();
      for (final contact in contacts) {
        final displayName = contact.displayName.toLowerCase();
        if (displayName.contains(lowerQuery) ||
            lowerQuery.contains(displayName)) {
          if (contact.phones.isNotEmpty) {
            final phone = contact.phones.first.number;
            print("ContactService: Found '${contact.displayName}' -> $phone");
            return {'name': contact.displayName, 'phone': phone};
          }
        }
      }

      print("ContactService: No contact found for '$query'");
      return null;
    } catch (e) {
      print("ContactService Error: $e");
      return null;
    }
  }

  /// Launch the phone dialer with the given number.
  Future<bool> makeCall(String phoneNumber) async {
    try {
      final uri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        print("ContactService: Launched call to $phoneNumber");
        return true;
      } else {
        print("ContactService: Cannot launch tel: URI");
        return false;
      }
    } catch (e) {
      print("ContactService Error making call: $e");
      return false;
    }
  }
}
