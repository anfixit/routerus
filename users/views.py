from django.shortcuts import render

from django.shortcuts import render, get_object_or_404
from django.contrib.auth.decorators import login_required
from .models import UserProfile
from .forms import UserProfileForm

@login_required
def edit_profile(request):
    user_profile, created = UserProfile.objects.get_or_create(user=request.user)
    if request.method == "POST":
        form = UserProfileForm(request.POST, instance=user_profile)
        if form.is_valid():
            form.save()
            return render(request, 'users/profile_success.html')
    else:
        form = UserProfileForm(instance=user_profile)

    return render(request, 'users/edit_profile.html', {'form': form})
