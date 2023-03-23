from django.db import models
from django.utils import timezone

class UnixDateTImeField(models.DateTimeField):
    def pre_save(self, model_instance, add: bool) -> any:
        value = super().pre_save(model_instance, add)
        if isinstance(value,int):
            value = timezone.make_aware(timezone.datetime.fromtimestamp(value))
        return value

class User(models.Model):
    uid = models.CharField(max_length=1024,primary_key=True)
    email = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now=False)
    
class Auth(models.Model):
    token = models.CharField(max_length=10240,primary_key=True)
    uid = models.CharField(max_length=1024)
    expired_at = UnixDateTImeField(auto_now=False,auto_now_add=False)
    
class Note(models.Model):
    class Meta:
        ordering = ['-updated_at']
    id = models.CharField(max_length=1024,primary_key=True)
    uid = models.CharField(max_length=1024)
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)