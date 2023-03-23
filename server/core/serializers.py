from rest_framework import serializers
from core import models

class NoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = models.Note
        fields = ['id','uid','content','created_at','updated_at']