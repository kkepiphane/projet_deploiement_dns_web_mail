from django.test import TestCase
from django.urls import reverse
from .models import Contact

class ContactTests(TestCase):
    def test_contact_creation(self):
        contact = Contact.objects.create(
            email="test@startup.tg",
            message="Test message"
        )
        self.assertEqual(contact.email, "test@startup.tg")